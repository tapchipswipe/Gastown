import Foundation
import CoreFoundation
import Darwin

public struct QuotaWindow: Sendable, Codable, Equatable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0.0, 100.0 - usedPercent)
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date >= resetsAt
    }
}

public struct CodexQuota: Sendable, Codable, Equatable {
    public let planType: String
    public let primary: QuotaWindow
    public let secondary: QuotaWindow?
    public let observedAt: Date

    public init(planType: String, primary: QuotaWindow, secondary: QuotaWindow? = nil, observedAt: Date = Date()) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.observedAt = observedAt
    }
}

public struct CodexQuotaReader: Sendable {
    public static var defaultCodexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Parses rate_limits payload from JSON data
    public static func parseRateLimits(from data: Data, observedAt: Date = Date()) -> CodexQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseRateLimits(json: json, observedAt: observedAt)
    }

    public static func parseRateLimits(json: [String: Any], observedAt: Date = Date()) -> CodexQuota? {
        let payload: [String: Any]
        if let rateLimits = json["rate_limits"] as? [String: Any] {
            payload = rateLimits
        } else if let p = json["payload"] as? [String: Any], let rateLimits = p["rate_limits"] as? [String: Any] {
            payload = rateLimits
        } else {
            payload = json
        }

        func number(_ value: Any?) -> Double? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        func window(_ value: Any?) -> QuotaWindow? {
            guard let dict = value as? [String: Any], let used = number(dict["used_percent"]),
                  let minutes = number(dict["window_minutes"]), let reset = number(dict["resets_at"]),
                  used.isFinite, (0...100).contains(used), minutes.isFinite, minutes.rounded() == minutes,
                  (1...Double(Int32.max)).contains(minutes), reset.isFinite, (0...253402300799).contains(reset) else { return nil }
            return QuotaWindow(usedPercent: used, windowMinutes: Int(minutes), resetsAt: Date(timeIntervalSince1970: reset))
        }
        guard let primaryWindow = window(payload["primary"]) else { return nil }
        let secondaryWindow = window(payload["secondary"])
        if payload["secondary"] != nil && !(payload["secondary"] is NSNull) && secondaryWindow == nil { return nil }
        let plan = (payload["plan_type"] as? String) ?? "unknown"
        return CodexQuota(planType: plan, primary: primaryWindow, secondary: secondaryWindow, observedAt: observedAt)
    }

    public static func readSnapshotAsync(codexHome: URL = defaultCodexHome) async -> QuotaSnapshot {
        let worker = Task.detached(priority: .utility) { readSnapshot(codexHome: codexHome) }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }
    public static func readSnapshot(codexHome: URL = defaultCodexHome, maximumEntries: Int = 10_000,
                                    maximumFiles: Int = 5, maximumBytes: Int = 1_048_576) -> QuotaSnapshot {
        let directory = codexHome.appendingPathComponent("sessions")
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return QuotaSnapshot(quota: nil, diagnostic: "Missing quota snapshot") }
        var candidates: [(URL, Date)] = []; var entries = 0; var limited = false
        for case let url as URL in iterator {
            if Task.isCancelled { return QuotaSnapshot(quota: nil, diagnostic: "Quota scan cancelled") }
            entries += 1
            if entries > min(10_000, max(0, maximumEntries)) { limited = true; break }
            guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            candidates.append((url, values.contentModificationDate ?? .distantPast))
            candidates.sort { $0.1 > $1.1 }; candidates = Array(candidates.prefix(min(5, max(0, maximumFiles))))
        }
        for (url, _) in candidates {
            if let quota = readQuotaFromRollout(url, maximumBytes: maximumBytes) {
                return QuotaSnapshot(quota: quota, diagnostic: limited ? "Discovery limited; snapshot may not be newest" : "Local source snapshot")
            }
        }
        return QuotaSnapshot(quota: nil, diagnostic: limited ? "Discovery limit reached; no valid snapshot" : (candidates.isEmpty ? "Missing quota snapshot" : "Invalid quota snapshot or no timestamp within bounded tail"))
    }
    public static func readQuotaFromRollout(_ fileURL: URL, maximumBytes: Int = 1_048_576) -> CodexQuota? {
        let fd = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return nil }
        let size = UInt64(info.st_size)
        let limit = UInt64(min(1_048_576, max(1, maximumBytes))), offset = size > limit ? size - limit : 0
        guard lseek(fd, off_t(offset), SEEK_SET) >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(limit))
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count >= 0 else { return nil }
        let data = Data(buffer.prefix(count))
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let raw = object["timestamp"] as? String,
                  let timestamp = fractional.date(from: raw) ?? formatter.date(from: raw),
                  let quota = parseRateLimits(json: object, observedAt: timestamp) else { continue }
            return quota
        }
        return nil
    }
}

public struct QuotaSnapshot: Sendable {
    public let quota: CodexQuota?
    public let diagnostic: String
    public init(quota: CodexQuota?, diagnostic: String) { self.quota = quota; self.diagnostic = diagnostic }
    public func description(at now: Date = Date()) -> String {
        guard let quota else { return diagnostic }
        if quota.observedAt > now.addingTimeInterval(60) { return "Invalid future timestamp · " + diagnostic }
        if quota.primary.isExpired(at: now) || quota.secondary?.isExpired(at: now) == true { return "Expired quota snapshot · " + diagnostic }
        if now.timeIntervalSince(quota.observedAt) > 900 { return "Stale quota snapshot (>15 minutes) · " + diagnostic }
        return "Recent advisory snapshot · " + diagnostic
    }
}
