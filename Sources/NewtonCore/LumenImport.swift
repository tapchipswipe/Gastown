import Foundation
import CryptoKit
import Darwin

public struct ImportBatch: Sendable {
    public let events: [HistoryEvent]
    public let skipped: Int
    public init(events: [HistoryEvent], skipped: Int = 0) { self.events = events; self.skipped = skipped }
}

public enum LumenImport {
    static let maximumBytes = 25 * 1024 * 1024
    public static func parse(_ data: Data) throws -> ImportBatch {
        guard data.count <= maximumBytes else { throw StoreError(message: "Lumen import is limited to 25 MB.") }
        var events: [HistoryEvent] = []; var skipped = 0
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data.split(separator: 10) {
            try Task.checkCancellation()
            guard line.count <= 1024 * 1024,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let kind = object["kind"] as? String, !kind.isEmpty, kind.utf8.count <= 100,
                  let timestamp = object["ts"] as? String,
                  let date = fractional.date(from: timestamp) ?? iso.date(from: timestamp),
                  let payload = object["payload"] as? [String: Any], let body = payload[kind] as? [String: Any],
                  payload["type"] == nil || payload["type"] as? String == kind,
                  let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { skipped += 1; continue }
            let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
            let title = (body["appName"] as? String) ?? (body["merchant"] as? String) ?? (body["repoName"] as? String) ?? kind
            let detail = (body["windowTitle"] as? String) ?? (body["url"] as? String) ?? (body["branch"] as? String) ?? kind
            let event = HistoryEvent(id: "lumen:\(digest)", timestamp: date, source: "Lumen · \(kind)", title: title, detail: detail)
            guard (try? EventStore.validate(event)) != nil else { skipped += 1; continue }
            guard events.count < 100_000 else { throw StoreError(message: "Split this file into batches smaller than 100,000 records.") }
            events.append(event)
        }
        return ImportBatch(events: events, skipped: skipped)
    }
    public static func read(_ url: URL) throws -> ImportBatch {
        guard url.isFileURL else { throw StoreError(message: "Choose a local file URL.") }
        // Open once and inspect that descriptor: path preflights alone allow replacement/growth races.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError(message: "Could not open the selected regular file (symbolic links are not imported).") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= maximumBytes else { throw StoreError(message: "Select a regular Lumen file no larger than 25 MB.") }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= maximumBytes - data.count else { throw StoreError(message: "The selected file grew beyond the 25 MB import limit.") }
            data.append(chunk)
        }
        return try parse(data)
    }
}
