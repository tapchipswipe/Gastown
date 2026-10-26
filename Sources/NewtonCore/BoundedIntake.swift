import Foundation
import Darwin

public struct IntakeLimits: Sendable {
    public var files = 100
    public var fileBytes = 4 * 1024 * 1024
    public var totalBytes = 16 * 1024 * 1024
    public var fields = 10_000
    public var directoryEntries = 10_000
    public init() {}
}
public struct IntakeReport: Sendable {
    public var events: [HistoryEvent] = []
    public var diagnostics: [String] = []
    public init() {}
}
public enum BoundedIntake {
    public static func read(_ url: URL, maximum: Int) throws -> Data {
        var remaining = maximum
        return try read(url, maximum: maximum, remainingTotal: &remaining)
    }
    static func read(_ url: URL, maximum: Int, remainingTotal: inout Int) throws -> Data {
        guard maximum >= 0, remainingTotal >= 0 else { throw StoreError(message: "Invalid byte limit") }
        guard url.isFileURL else { throw StoreError(message: "Local file required") }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError(message: "Cannot open \(url.lastPathComponent)") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maximum, info.st_size <= remainingTotal else {
            throw StoreError(message: "Not a regular file or exceeds file/remaining total byte limit (\(maximum)/\(remainingTotal))")
        }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let n = Darwin.read(fd, &buffer, min(buffer.count, max(1, min(maximum - result.count, remainingTotal))))
            if n == 0 { return result }
            guard n > 0 else { throw StoreError(message: "Read failed") }
            let allowance = remainingTotal
            remainingTotal = max(0, remainingTotal - n)
            guard n <= allowance, n <= maximum - result.count else { throw StoreError(message: "File/total byte limit exceeded") }
            result.append(contentsOf: buffer.prefix(n))
        }
    }
    public static func load(_ directory: URL, extensions: Set<String>, limits: IntakeLimits = IntakeLimits(),
                            parse: (Data, URL, Date) throws -> [HistoryEvent]) throws -> IntakeReport {
        var report = IntakeReport(), entries = 0, files = 0, remainingTotal = limits.totalBytes
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            report.diagnostics = ["Directory unavailable: \(directory.path)"]; return report
        }
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
            // Enumerator invokes this synchronously while advancing; retain skipped-subtree evidence.
            report.diagnostics.append("Skipped discovery at \(url.lastPathComponent): \(error.localizedDescription)")
            return true
        }) else {
            report.diagnostics.append("Directory unavailable: \(directory.path)"); return report
        }
        for case let url as URL in iterator {
            try Task.checkCancellation(); entries += 1
            guard entries <= limits.directoryEntries else { report.diagnostics.append("Discovery stopped at \(limits.directoryEntries) entries; remaining files unexamined"); break }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            guard files < limits.files else { report.diagnostics.append("Skipped \(url.lastPathComponent): \(limits.files) file limit"); continue }
            files += 1
            do {
                guard remainingTotal > 0 else { report.diagnostics.append("Skipped \(url.lastPathComponent): \(limits.totalBytes) total byte limit"); continue }
                let data = try read(url, maximum: limits.fileBytes, remainingTotal: &remainingTotal)
                let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date(timeIntervalSince1970: 0)
                let parsed = try parse(data, url, date)
                for event in parsed { try EventStore.validate(event) }
                report.events += parsed
            } catch is CancellationError { throw CancellationError() }
            catch { report.diagnostics.append("Skipped \(url.lastPathComponent): \(error)") }
        }
        return report
    }
}
