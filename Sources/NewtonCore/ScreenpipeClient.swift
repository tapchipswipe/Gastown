import Foundation
import CoreFoundation

public struct ScreenpipeResult: Sendable {
    public let events: [HistoryEvent]
    public let omitted: Int
    public init(events: [HistoryEvent], omitted: Int = 0) { self.events = events; self.omitted = omitted }
}
public protocol ScreenpipeSearching: Sendable {
    func search(_ query: String, token: String) async throws -> ScreenpipeResult
}

public struct ScreenpipeClient: ScreenpipeSearching {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = BoundedHTTPTransport()) { self.transport = transport }
    public func search(_ query: String, token: String = "") async throws -> ScreenpipeResult {
        try Task.checkCancellation()
        guard query.utf8.count <= 4096, !query.contains("\0"), token.utf8.count <= 4096,
              token.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e }) else {
            throw StoreError(message: "Use a query under 4 KB and an API token without spaces or control characters.")
        }
        var components = URLComponents(string: "http://127.0.0.1:3030/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "30"),
                                URLQueryItem(name: "content_type", value: "all")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8; request.httpShouldHandleCookies = false
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data = try await transport.data(for: request, maximumBytes: 8 * 1024 * 1024)
        try Task.checkCancellation()
        return try Self.decodeResponse(data)
    }
    public static func decode(_ data: Data) throws -> [HistoryEvent] { try decodeResponse(data).events }
    public static func decodeResponse(_ data: Data) throws -> ScreenpipeResult {
        guard data.count <= 8 * 1024 * 1024 else { throw StoreError(message: "Screenpipe response exceeds 8 MB.") }
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = response["data"] as? [[String: Any]] else {
            throw StoreError(message: "Unrecognized Screenpipe response. Results were not changed.")
        }
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var seen = Set<String>(); var result: [HistoryEvent] = []
        for row in rows.prefix(30) {
            try Task.checkCancellation()
            guard let type = row["type"] as? String,
                  ["ocr", "audio", "ui", "input", "accessibility", "memory", "parsed"].contains(type.lowercased()),
                  let content = row["content"] as? [String: Any], let rawTime = content["timestamp"] as? String,
                  let date = fractional.date(from: rawTime) ?? iso.date(from: rawTime),
                  let rawID = content["id"] ?? content["frame_id"] ?? content["chunk_id"],
                  let recordID = Self.identity(rawID) else { continue }
            let id = "screenpipe:\(type.lowercased()):\(recordID)"
            let text = (content["text"] as? String) ?? (content["transcription"] as? String) ?? ""
            let title = (content["app_name"] as? String) ?? (content["device_name"] as? String) ?? type
            let event = HistoryEvent(id: id, timestamp: date, source: "Screenpipe · \(type)",
                                     title: String(title.prefix(4000)), detail: String(text.prefix(12_000)))
            guard (try? EventStore.validate(event)) != nil, seen.insert(id).inserted else { continue }
            result.append(event)
        }
        return ScreenpipeResult(events: result, omitted: rows.count - result.count)
    }
    private static func identity(_ value: Any) -> String? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue else { return nil }
            return number.stringValue
        }
        if let value = value as? String, !value.isEmpty, value.utf8.count <= 400,
           !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return value }
        return nil
    }
}
