import Foundation

public enum ProjectCondition: String, Sendable, Codable { case clean, dirty, unavailable }
public struct TrackedProject: Sendable, Codable, Equatable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let activeBranch: String
    public let condition: ProjectCondition
    public var isDirty: Bool { condition == .dirty }
    public let lastCommitMessage: String
    public let lastCommitDate: Date?
}
public struct ProjectAtlasScanner: Sendable {
    public static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saved = UserDefaults.standard.stringArray(forKey: "Newton.repositoryRoots")
        return saved?.map { URL(fileURLWithPath: $0) } ?? [home, home.appendingPathComponent("Projects"), home.appendingPathComponent("repos"), home.appendingPathComponent("local/repos")]
    }
    public static func scanProjects(in roots: [URL] = defaultSearchRoots) async -> [TrackedProject] {
        let discovery = Task.detached(priority: .utility) { discover(roots) }
        let urls = await withTaskCancellationHandler { await discovery.value } onCancel: { discovery.cancel() }
        var projects: [TrackedProject] = []
        for url in Set(urls) {
            if Task.isCancelled { break }
            projects.append(await inspectRepo(at: url))
        }
        return projects.sorted {
            let left = $0.lastCommitDate ?? .distantPast, right = $1.lastCommitDate ?? .distantPast
            return left == right ? $0.path < $1.path : left > right
        }
    }
    static func discover(_ roots: [URL]) -> [URL] {
        let pruned: Set<String> = ["node_modules", ".venv", "venv", ".build", "target", "Library", "Documents", "Desktop", "Downloads", "archive", "archives", "icloud-recovery", "__pycache__", "Pods", "Carthage"]
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var found: [URL] = [], entries = 0
        for root in roots {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) { found.append(root); continue }
            let shallow = root.standardizedFileURL == home
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator {
                entries += 1
                if entries > 10_000 || Task.isCancelled { return found }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true, !pruned.contains(url.lastPathComponent) else { iterator.skipDescendants(); continue }
                if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { found.append(url); iterator.skipDescendants() }
                else if shallow { iterator.skipDescendants() }
            }
        }
        return found
    }
    public static func inspectRepo(at url: URL) async -> TrackedProject {
        func unavailable(_ reason: String) -> TrackedProject {
            TrackedProject(name: url.lastPathComponent, path: url.path, activeBranch: "Unavailable",
                           condition: .unavailable, lastCommitMessage: reason, lastCommitDate: nil)
        }
        do {
            let runner = ProcessRunner()
            let head = try await runner.run("/usr/bin/git", ["rev-parse", "--abbrev-ref", "HEAD"], directory: url)
            let status = try await runner.run("/usr/bin/git", ["status", "--porcelain", "-z"], directory: url)
            let log = try await runner.run("/usr/bin/git", ["log", "-1", "--format=%ct|%s"], directory: url)
            guard head.exitCode == 0, status.exitCode == 0, log.exitCode == 0, !head.truncated, !log.truncated else { return unavailable("Git inspection failed") }
            let parts = log.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let epoch = Double(parts[0]), epoch.isFinite else { return unavailable("Commit metadata unavailable") }
            return TrackedProject(name: url.lastPathComponent, path: url.path,
                                  activeBranch: head.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                                  condition: status.stdout.isEmpty && !status.truncated ? .clean : .dirty,
                                  lastCommitMessage: String(parts[1]), lastCommitDate: Date(timeIntervalSince1970: epoch))
        } catch { return unavailable("Git unavailable: \(error)") }
    }
}
