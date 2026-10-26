import Foundation
import Darwin

public struct DeveloperProjectCandidate: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let projectName: String
    public let projectPath: String
    public let bloatPath: String
    public let bloatType: String
    public let sizeBytes: Int64
    public let sizeComplete: Bool
    public var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) + (sizeComplete ? " estimated" : " partial estimate") }
}
public struct CleanupScan: Sendable {
    public let candidates: [DeveloperProjectCandidate]
    public let diagnostics: [String]
    public let isComplete: Bool
    public init(candidates: [DeveloperProjectCandidate] = [], diagnostics: [String] = [], isComplete: Bool = true) {
        self.candidates = candidates; self.diagnostics = diagnostics; self.isComplete = isComplete
    }
}
public struct CleanupOutcome: Sendable, Identifiable {
    public enum Status: String, Sendable { case removed, failed, cancelled }
    public var id: UUID { candidate.id }
    public let candidate: DeveloperProjectCandidate
    public let status: Status
    public let detail: String
}

/// Off-main, sequential owner of scan authorization and deletion. No arbitrary-path delete API.
public actor DeveloperProjectTrimmer {
    public static let standardTargets = ["node_modules", ".venv", "venv", "target", ".build", ".turbo", ".next"]
    private struct Identity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    }
    private struct Issued: Sendable {
        let candidate: DeveloperProjectCandidate
        let root: String
        let rootIdentity: Identity
        let projectIdentity: Identity
        let cacheIdentity: Identity
    }
    private var issued: [UUID: Issued] = [:]
    private let discoveryLimit: Int
    private let sizingLimit: Int
    public init(discoveryLimit: Int = 10_000, sizingLimit: Int = 100_000) {
        self.discoveryLimit = max(1, min(discoveryLimit, 10_000))
        self.sizingLimit = max(1, min(sizingLimit, 100_000))
    }
    public func scan(roots: [String]? = nil, minimumBytes: Int64 = 1_000_000) throws -> CleanupScan {
        issued = [:]
        let home = NSHomeDirectory()
        let roots = roots ?? ["\(home)/Projects", "\(home)/repos", "\(home)/local/repos", "\(home)/Developer", "\(home)/Code", "\(home)/workspace"]
        var candidates: [DeveloperProjectCandidate] = [], diagnostics: [String] = [], entries = 0
        var seen = Set<String>()
        for path in roots {
            try Task.checkCancellation()
            let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(root.path).inserted else { continue }
            do {
                let rootIdentity = try Self.directoryIdentity(root.path)
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [], errorHandler: { url, error in
                    diagnostics.append("\(url.path): \(error.localizedDescription)"); return true
                })
                guard let enumerator else { throw StoreError(message: "Cannot enumerate \(root.path)") }
                // Include a root that is itself a project, as well as nested project directories.
                var next: URL? = root
                while let url = next {
                    try Task.checkCancellation()
                    if entries >= discoveryLimit { diagnostics.append("Discovery limited to \(discoveryLimit) entries"); break }
                    entries += 1
                    let info = try Self.info(url.path)
                    if info.st_mode & S_IFMT != S_IFDIR {
                        if info.st_mode & S_IFMT == S_IFLNK { enumerator.skipDescendants() }
                    } else if url != root && (Self.standardTargets.contains(url.lastPathComponent) || url.lastPathComponent == ".git") {
                        enumerator.skipDescendants()
                    } else {
                        let projectMarkers = [".git", "Package.swift", "package.json", "Cargo.toml", "pyproject.toml"]
                        if projectMarkers.contains(where: { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }) {
                            for target in Self.standardTargets {
                                try Task.checkCancellation()
                                let cache = url.appendingPathComponent(target)
                                var info = stat()
                                guard lstat(cache.path, &info) == 0 else {
                                    if errno != ENOENT { diagnostics.append("Cannot inspect \(cache.path): \(String(cString: strerror(errno)))") }
                                    continue
                                }
                                guard info.st_mode & S_IFMT == S_IFDIR else {
                                    if info.st_mode & S_IFMT == S_IFLNK { diagnostics.append("Skipped symbolic link: \(cache.path)") }
                                    continue
                                }
                                let (size, complete, errors) = try sizeDirectory(cache)
                                diagnostics += errors
                                if !complete { diagnostics.append("Incomplete size: \(cache.path)") }
                                if size >= minimumBytes {
                                    let candidate = DeveloperProjectCandidate(id: UUID(), projectName: url.lastPathComponent, projectPath: url.path,
                                        bloatPath: cache.path, bloatType: target, sizeBytes: size, sizeComplete: complete)
                                    issued[candidate.id] = Issued(candidate: candidate, root: root.path, rootIdentity: rootIdentity,
                                        projectIdentity: Identity(try Self.info(url.path)), cacheIdentity: Identity(info))
                                    candidates.append(candidate)
                                }
                            }
                        }
                    }
                    next = enumerator.nextObject() as? URL
                }
            } catch is CancellationError { issued = [:]; throw CancellationError() }
            catch { diagnostics.append("\(root.path): \(error.localizedDescription)") }
            if entries >= discoveryLimit { break }
        }
        return CleanupScan(candidates: candidates.sorted { $0.sizeBytes == $1.sizeBytes ? $0.bloatPath < $1.bloatPath : $0.sizeBytes > $1.sizeBytes }, diagnostics: diagnostics, isComplete: diagnostics.isEmpty)
    }
    private func sizeDirectory(_ url: URL) throws -> (Int64, Bool, [String]) {
        var diagnostics: [String] = [], total: Int64 = 0, entries = 0, complete = true
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [], options: [], errorHandler: { url, error in
            diagnostics.append("\(url.path): \(error.localizedDescription)"); return true
        }) else { return (0, false, ["Cannot size \(url.path)"]) }
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            if entries >= sizingLimit { complete = false; break }
            entries += 1
            do {
                let value = try Self.info(file.path)
                if value.st_mode & S_IFMT == S_IFREG { total += Int64(value.st_size) }
                if value.st_mode & S_IFMT == S_IFLNK { enumerator.skipDescendants() }
            } catch { diagnostics.append(error.localizedDescription) }
        }
        return (total, complete && diagnostics.isEmpty, diagnostics)
    }
    public func trim(_ candidates: [DeveloperProjectCandidate]) -> [CleanupOutcome] {
        var results: [CleanupOutcome] = []
        for candidate in candidates {
            if Task.isCancelled {
                results.append(CleanupOutcome(candidate: candidate, status: .cancelled, detail: "Cancelled before this directory; an in-progress deletion cannot be rolled back")); continue
            }
            do {
                guard let authorization = issued.removeValue(forKey: candidate.id), authorization.candidate == candidate else {
                    throw StoreError(message: "Candidate was not issued by the current scan or has already been attempted")
                }
                try Self.remove(authorization)
                results.append(CleanupOutcome(candidate: candidate, status: .removed, detail: "Removed directory · estimated size \(candidate.sizeFormatted); free-space gain is not measured"))
            } catch {
                results.append(CleanupOutcome(candidate: candidate, status: .failed, detail: error.localizedDescription + " · some contents may already be removed"))
            }
        }
        return results
    }
    private static func info(_ path: String) throws -> stat {
        var value = stat()
        guard lstat(path, &value) == 0 else { throw failure("Inspect", path) }
        return value
    }
    private static func directoryIdentity(_ path: String) throws -> Identity {
        let value = try info(path)
        guard value.st_mode & S_IFMT == S_IFDIR else { throw StoreError(message: "Not a regular directory: \(path)") }
        return Identity(value)
    }
    private static func failure(_ action: String, _ path: String) -> StoreError {
        StoreError(message: "\(action) \(path): \(String(cString: strerror(errno)))")
    }
    private static func remove(_ entry: Issued) throws {
        let candidate = entry.candidate
        let project = URL(fileURLWithPath: candidate.projectPath).standardizedFileURL
        let cache = URL(fileURLWithPath: candidate.bloatPath).standardizedFileURL
        guard project.path == project.resolvingSymlinksInPath().path,
              cache.path == cache.resolvingSymlinksInPath().path,
              cache.deletingLastPathComponent() == project,
              standardTargets.contains(cache.lastPathComponent),
              project.path == entry.root || project.path.hasPrefix(entry.root + "/"),
              try directoryIdentity(entry.root) == entry.rootIdentity,
              try directoryIdentity(project.path) == entry.projectIdentity,
              try directoryIdentity(cache.path) == entry.cacheIdentity else {
            throw StoreError(message: "Refusing changed identity, symbolic link, or out-of-root cache: \(cache.path)")
        }
        let rootFD = open(entry.root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw failure("Open root", entry.root) }
        defer { close(rootFD) }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0, Identity(rootInfo) == entry.rootIdentity else { throw StoreError(message: "Root identity changed") }
        var parentFD = dup(rootFD)
        guard parentFD >= 0 else { throw failure("Duplicate root", entry.root) }
        defer { close(parentFD) }
        let relative = project.path == entry.root ? "" : String(project.path.dropFirst(entry.root.count + 1))
        for component in relative.split(separator: "/") {
            let next = openat(parentFD, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw failure("Open project component", String(component)) }
            close(parentFD); parentFD = next
        }
        var projectInfo = stat()
        guard fstat(parentFD, &projectInfo) == 0, Identity(projectInfo) == entry.projectIdentity else { throw StoreError(message: "Project identity changed") }
        // Every recursion stays relative to pinned directory descriptors; links are unlinked, never traversed.
        try removeDirectory(parent: parentFD, name: cache.lastPathComponent, expected: entry.cacheIdentity, depth: 0)
    }
    private static func removeDirectory(parent: Int32, name: String, expected: Identity, depth: Int) throws {
        guard depth < 256 else { throw StoreError(message: "Cleanup depth limit reached") }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Open cache", name) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, Identity(info) == expected else { throw StoreError(message: "Directory identity changed: \(name)") }
        let duplicate = dup(fd)
        guard duplicate >= 0 else { throw failure("Duplicate directory", name) }
        guard let directory = fdopendir(duplicate) else { close(duplicate); throw failure("Read directory", name) }
        defer { closedir(directory) }
        while true {
            errno = 0
            guard let child = readdir(directory) else {
                if errno != 0 { throw failure("Read directory", name) }
                break
            }
            let childName = withUnsafePointer(to: &child.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if childName == "." || childName == ".." { continue }
            var childInfo = stat()
            guard fstatat(fd, childName, &childInfo, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("Inspect child", childName) }
            if childInfo.st_mode & S_IFMT == S_IFDIR {
                try removeDirectory(parent: fd, name: childName, expected: Identity(childInfo), depth: depth + 1)
            } else {
                guard unlinkat(fd, childName, 0) == 0 else { throw failure("Remove child", childName) }
            }
        }
        var current = stat()
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0, Identity(current) == expected,
              current.st_mode & S_IFMT == S_IFDIR else { throw StoreError(message: "Cache identity changed before removal: \(name)") }
        guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw failure("Remove directory", name) }
    }
}
