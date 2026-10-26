import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let truncated: Bool
}
public enum RunnerError: Error, Sendable { case launch(Int32), timedOut(ProcessResult), cancelled(ProcessResult) }

/// One owned process group; blocking POSIX I/O is confined to a detached worker.
public struct ProcessRunner: Sendable {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], directory: URL,
                    timeout: TimeInterval = 5, outputLimit: Int = 1_048_576,
                    progress: (@Sendable (String, Bool) -> Void)? = nil) async throws -> ProcessResult {
        let worker = Task.detached(priority: .utility) {
            try Self.execute(executable, arguments, directory: directory, timeout: timeout,
                             outputLimit: max(1, outputLimit), progress: progress)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private static func execute(_ executable: String, _ arguments: [String], directory: URL,
                                timeout: TimeInterval, outputLimit: Int,
                                progress: (@Sendable (String, Bool) -> Void)?) throws -> ProcessResult {
        try Task.checkCancellation()
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { throw RunnerError.launch(errno) }
        guard pipe(&err) == 0 else { close(out[0]); close(out[1]); throw RunnerError.launch(errno) }
        defer { for fd in out + err { close(fd) } }
        guard fcntl(out[0], F_SETFL, O_NONBLOCK) >= 0, fcntl(err[0], F_SETFL, O_NONBLOCK) >= 0 else { throw RunnerError.launch(errno) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO)
        for fd in out + err { posix_spawn_file_actions_addclose(&actions, fd) }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let code = argv.withUnsafeBufferPointer {
            posix_spawn(&pid, executable, &actions, &attr, $0.baseAddress!, environ)
        }
        guard code == 0 else { throw RunnerError.launch(code) }
        // Only this worker owns the descriptors and child; no cross-thread Process mutation.
        close(out[1]); out[1] = -1; close(err[1]); err[1] = -1
        var stdout = Data(), stderr = Data(), tail = Data()
        var truncated = false, ended = false, outEOF = false, errEOF = false
        var status: Int32 = 0
        let clock = ContinuousClock(), start = ContinuousClock.now
        var lastProgress = start, termination: ContinuousClock.Instant?
        var cancelled = false, expired = false
        func retain(_ chunk: Data, in data: inout Data) {
            data.append(chunk)
            if data.count > outputLimit { data.removeFirst(data.count - outputLimit); truncated = true }
        }
        while true {
            let now = clock.now
            if termination == nil && (Task.isCancelled || start.duration(to: now) >= .seconds(timeout)) {
                cancelled = Task.isCancelled; expired = !cancelled
                termination = now; kill(-pid, SIGTERM)
            }
            if let termination, termination.duration(to: now) >= .seconds(2) { kill(-pid, SIGKILL) }
            for index in 0..<2 {
                let fd = index == 0 ? out[0] : err[0]
                var buffer = [UInt8](repeating: 0, count: 16384)
                // Bounded work per iteration ensures a flooding child cannot starve deadlines.
                for _ in 0..<16 {
                    let n = read(fd, &buffer, buffer.count)
                    if n > 0 {
                        let chunk = Data(buffer.prefix(n))
                        if index == 0 { retain(chunk, in: &stdout) } else { retain(chunk, in: &stderr) }
                        retain(chunk, in: &tail)
                    } else {
                        if n == 0 { if index == 0 { outEOF = true } else { errEOF = true } }
                        break
                    }
                }
            }
            if !ended { ended = waitpid(pid, &status, WNOHANG) == pid }
            if lastProgress.duration(to: now) >= .milliseconds(200) {
                progress?(String(decoding: tail, as: UTF8.self), truncated); lastProgress = now
            }
            if ended && outEOF && errEOF { break }
            // Descendants may retain pipes after the leader exits. Kill their group at the deadline.
            if ended, let termination, termination.duration(to: now) >= .seconds(2.1) { break }
            usleep(10_000)
        }
        if !ended { while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
        // Closing both pipes and reaping the leader do not prove its descendants exited.
        // Finish group teardown even when a silent child survives the leader's TERM/normal exit.
        if kill(-pid, 0) == 0 {
            let grace = termination ?? clock.now
            if termination == nil { kill(-pid, SIGTERM) }
            while kill(-pid, 0) == 0 && grace.duration(to: clock.now) < .seconds(2) { usleep(10_000) }
            if kill(-pid, 0) == 0 { kill(-pid, SIGKILL) }
        }
        func decode(_ data: Data) -> String {
            var value = String(decoding: data, as: UTF8.self)
            while value.utf8.count > outputLimit { value.removeFirst() }
            return value
        }
        let result = ProcessResult(exitCode: (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f),
                                   stdout: decode(stdout), stderr: decode(stderr), truncated: truncated)
        if cancelled { throw RunnerError.cancelled(result) }
        if expired { throw RunnerError.timedOut(result) }
        return result
    }
}
