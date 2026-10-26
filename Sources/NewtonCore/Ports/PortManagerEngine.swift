import Foundation
import Darwin

public struct PortEntry: Identifiable, Sendable, Equatable {
    public var id: String { "\(pid):\(port)" }
    public let pid: pid_t
    public let port: Int
    public let processName: String
    public let user: String
    public let address: String
    public let processIdentity: String?

    public init(pid: pid_t, port: Int, processName: String, user: String, address: String, processIdentity: String? = nil) {
        self.pid = pid
        self.port = port
        self.processName = processName
        self.user = user
        self.address = address
        self.processIdentity = processIdentity
    }
}

/// Developer Port Manager Engine: inspects active localhost listening ports and terminates hung processes.
public enum PortManagerEngine: Sendable {
    /// Scans system for processes listening on TCP ports.
    public static func scanActivePorts() async throws -> [PortEntry] {
        let result = try await ProcessRunner().run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-n", "-P"], directory: URL(fileURLWithPath: "/"), timeout: 5, outputLimit: 1_048_576)
        guard !result.truncated, result.exitCode == 0 || result.exitCode == 1 else { throw StoreError(message: "Port inspection incomplete or failed") }
        return parseLsofOutput(result.stdout).map { entry in
            PortEntry(pid: entry.pid, port: entry.port, processName: entry.processName, user: entry.user, address: entry.address, processIdentity: identity(entry.pid))
        }
    }
    private static func identity(_ pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid() else { return nil }
        return "\(pid):\(info.pbi_uid):\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    /// Parses output lines from `lsof -iTCP -sTCP:LISTEN -n -P`.
    public static func parseLsofOutput(_ output: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            // Expecting: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            guard parts.count >= 9 else { continue }
            if parts[0] == "COMMAND" { continue }

            let processName = parts[0]
            guard let pid = pid_t(parts[1]) else { continue }
            let user = parts[2]
            let nameField = parts[8] // e.g. "*:3000" or "127.0.0.1:8080" or "[::1]:5173"

            guard let colonIdx = nameField.lastIndex(of: ":") else { continue }
            let portStr = String(nameField[nameField.index(after: colonIdx)...])
            guard let port = Int(portStr) else { continue }

            let address = String(nameField[..<colonIdx])

            let entry = PortEntry(
                pid: pid,
                port: port,
                processName: processName,
                user: user,
                address: address
            )

            if !entries.contains(where: { $0.pid == pid && $0.port == port }) {
                entries.append(entry)
            }
        }

        return entries.sorted { $0.port < $1.port }
    }

    /// Confirmation belongs to the UI; immediately revalidate PID birth time and listener before signaling.
    @discardableResult public static func terminatePort(_ entry: PortEntry, force: Bool = false) async throws -> Bool {
        guard entry.pid > 1, let expected = entry.processIdentity, identity(entry.pid) == expected else { throw StoreError(message: "Process identity unavailable or changed; refresh before terminating") }
        let current = try await scanActivePorts()
        guard current.contains(where: { $0 == entry }), identity(entry.pid) == expected else { throw StoreError(message: "Listener or process changed; no signal sent") }
        guard kill(entry.pid, force ? SIGKILL : SIGTERM) == 0 else { throw StoreError(message: "Could not signal process (\(errno))") }
        // Signal success does not prove termination. A reused PID also counts as original exit.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if identity(entry.pid) != expected { return true }
        }
        return false
    }
}
