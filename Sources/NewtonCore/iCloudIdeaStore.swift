import Foundation
import CryptoKit
import Darwin

public struct iCloudIdeaStore: Sendable {
    public static var defaultICloudIdeasDirectory: URL {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Newton/Ideas")
        return docs
    }

    public static var fallbackLocalIdeasDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Newton/Ideas")
    }

    /// Discovers active ideas directory (prefers iCloud if exists, falls back to local)
    public static func resolveIdeasDirectory() -> URL {
        let icloud = defaultICloudIdeasDirectory
        if FileManager.default.fileExists(atPath: icloud.path) {
            return icloud
        }
        return fallbackLocalIdeasDirectory
    }

    public static func readReport(from directory: URL, limits: IntakeLimits = IntakeLimits()) throws -> IntakeReport {
        try BoundedIntake.load(directory, extensions: ["md", "txt"], limits: limits) { data, url, date in
            try parseIdea(data, url: url, date: date)

        }
    }

    public static func readIdea(_ url: URL) throws -> [HistoryEvent] {
        let data = try BoundedIntake.read(url, maximum: 4 * 1024 * 1024)
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return try parseIdea(data, url: url, date: date)
    }
    private static func parseIdea(_ data: Data, url: URL, date: Date) throws -> [HistoryEvent] {
            guard let content = String(data: data, encoding: .utf8) else { throw StoreError(message: "Invalid UTF-8") }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            let candidate = lines[0].trimmingCharacters(in: CharacterSet(charactersIn: "#*- ").union(.whitespaces))
            let title = candidate.isEmpty ? url.deletingPathExtension().lastPathComponent : candidate
            let body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            let digest = SHA256.hash(data: Data("\(url.lastPathComponent):\(trimmed)".utf8)).map { String(format: "%02x", $0) }.joined()
            return [HistoryEvent(id: "idea:" + digest, timestamp: date, source: "iCloud Idea", title: title, detail: body)]
    }

    /// Writes a new idea note to disk
    @discardableResult
    public static func saveIdea(title: String, detail: String = "", in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let safeFilename = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        var slug = ""
        for character in safeFilename {
            guard slug.utf8.count + String(character).utf8.count <= 60 else { break }
            slug.append(character)
        }
        let filename = (slug.isEmpty ? "idea" : slug) + "-" + UUID().uuidString + ".md"
        let fileURL = directory.appendingPathComponent(filename)
        let fileContent = "# \(title)\n\n\(detail)\n"
        // Atomic publication, with exclusive creation: an existing note is never replaced.
        let staged = directory.appendingPathComponent(".idea-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try Data(fileContent.utf8).write(to: staged, options: .withoutOverwriting)
        guard Darwin.link(staged.path, fileURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return fileURL
    }
}
