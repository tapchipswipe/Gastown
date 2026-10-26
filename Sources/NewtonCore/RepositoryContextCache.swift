import Foundation
import CryptoKit

public actor RepositoryContextCache {
    private struct Entry: Codable, Sendable { let fingerprint: String; let project: TrackedProject }
    private let store: IntelligenceStore
    public init(store: IntelligenceStore) { self.store = store }
    public func roots() async throws -> [String] {
        try await store.load([String].self,namespace: "settings",id: "repository-roots") ?? ProjectAtlasScanner.defaultSearchRoots.map(\.path)
    }
    public func setRoots(_ paths: [String]) async throws {
        guard paths.count <= 20, paths.allSatisfy({ $0.hasPrefix("/") && !$0.isEmpty }) else { throw StoreError(message: "Choose at most 20 absolute repository roots") }
        try await store.save(paths,namespace: "settings",id: "repository-roots")
    }
    private static func fingerprint(_ root: URL) -> String? {
        let fm = FileManager.default
        var digest = SHA256(), visited = 0
        let excluded: Set<String> = ["node_modules",".build",".venv","venv","target",".next",".turbo","objects","logs","build"]
        guard let enumerator = fm.enumerator(at: root,includingPropertiesForKeys: [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey],options: [.skipsPackageDescendants]) else { return nil }
        var entries: [String] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return nil }; visited += 1
            if visited > 10_000 { return nil }
            guard let attributes = try? url.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey]) else { return nil }
            if attributes.isSymbolicLink == true || excluded.contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
            entries.append(url.path + ":\(attributes.fileSize ?? 0):\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        // A .git file points outside a worktree; treat it as uncacheable to avoid stale refs.
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: root.appendingPathComponent(".git").path,isDirectory: &directory), directory.boolValue else { return nil }
        for entry in entries.sorted() { digest.update(data: Data(entry.utf8)) }
        return digest.finalize().map { String(format: "%02x",$0) }.joined()
    }
    public func refresh() async throws -> [TrackedProject] {
        let roots = try await roots().map { URL(fileURLWithPath: $0) }
        let discovery = Task.detached(priority: .utility) { ProjectAtlasScanner.discover(roots) }
        let urls = await withTaskCancellationHandler { await discovery.value } onCancel: { discovery.cancel() }
        var result: [TrackedProject] = []
        for url in Set(urls) {
            try Task.checkCancellation()
            let worker = Task.detached(priority: .utility) { Self.fingerprint(url) }
            let fingerprint = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            if let fingerprint, let cached = try await store.load(Entry.self,namespace: "repository-cache",id: url.path), cached.fingerprint == fingerprint {
                result.append(cached.project); continue
            }
            let project = await ProjectAtlasScanner.inspectRepo(at: url)
            if fingerprint != nil,project.condition != .unavailable,let refreshed = Self.fingerprint(url) { try await store.save(Entry(fingerprint: refreshed,project: project),namespace: "repository-cache",id: url.path) }
            result.append(project)
        }
        return result.sorted { ($0.lastCommitDate ?? .distantPast) > ($1.lastCommitDate ?? .distantPast) }
    }
}
