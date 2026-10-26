import Foundation
import Testing
@testable import NewtonCore

struct CleanupTests {
    func fixture(_ names: [String] = ["node_modules", ".build"]) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let project = root.appendingPathComponent("nested/project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "{}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        for name in names {
            let cache = project.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data(repeating: 65, count: 1_100_000).write(to: cache.appendingPathComponent(".hidden-payload"))
        }
        return (root, project)
    }
    @Test func onlyCurrentScanCandidatesCanBeDeletedAndHiddenFilesCount() async throws {
        let (root, project) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = DeveloperProjectTrimmer()
        let first = try await service.scan(roots: [root.path])
        #expect(first.isComplete && first.candidates.count == 2)
        #expect(first.candidates.allSatisfy { $0.sizeBytes == 1_100_000 })
        let current = try await service.scan(roots: [root.path])
        let old = await service.trim(first.candidates)
        #expect(old.allSatisfy { $0.status == .failed })
        let outcomes = await service.trim(current.candidates)
        #expect(outcomes.allSatisfy { $0.status == .removed })
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("package.json").path))
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("node_modules").path) == false)
        #expect(outcomes.allSatisfy { $0.detail.contains("estimated") && $0.detail.contains("not measured") })
    }
    @Test func pathSubstitutionAndSymlinkCannotRemoveOutsideData() async throws {
        let (root, project) = try fixture(["node_modules"]); defer { try? FileManager.default.removeItem(at: root) }
        let service = DeveloperProjectTrimmer()
        let scan = try await service.scan(roots: [root.path])
        let cache = project.appendingPathComponent("node_modules"), retained = project.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: cache, to: retained)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: retained)
        let outcomes = await service.trim(scan.candidates)
        #expect(outcomes.first?.status == .failed)
        #expect(FileManager.default.fileExists(atPath: retained.appendingPathComponent(".hidden-payload").path))
        let links = try await service.scan(roots: [root.path])
        #expect(links.candidates.isEmpty && !links.isComplete)
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let replacement = await service.trim(scan.candidates)
        #expect(replacement.first?.status == .failed)
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }
    @Test func changedIdentityMissingFolderAndPartialFailureArePerDirectory() async throws {
        let (root, project) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = DeveloperProjectTrimmer(), cache = project.appendingPathComponent("node_modules")
        let scan = try await service.scan(roots: [root.path])
        try FileManager.default.moveItem(at: cache, to: project.appendingPathComponent("retained"))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let results = await service.trim(scan.candidates)
        #expect(results.filter { $0.status == .removed }.count == 1)
        #expect(results.filter { $0.status == .failed }.count == 1)
        let rescan = try await service.scan(roots: [root.path], minimumBytes: 0)
        try FileManager.default.removeItem(at: cache)
        let missing = await service.trim(rescan.candidates)
        #expect(missing.first?.status == .failed)
        let missingRoot = try await service.scan(roots: [root.appendingPathComponent("absent").path])
        #expect(missingRoot.isComplete == false && missingRoot.diagnostics.isEmpty == false)
    }
    @Test func projectSubstitutionAndNestedLinksAreSafe() async throws {
        let (root, project) = try fixture(["node_modules"]); defer { try? FileManager.default.removeItem(at: root) }
        let service = DeveloperProjectTrimmer()
        let scan = try await service.scan(roots: [root.path])
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: project, to: moved)
        try FileManager.default.createSymbolicLink(at: project, withDestinationURL: moved)
        #expect(await service.trim(scan.candidates).first?.status == .failed)
        try FileManager.default.removeItem(at: project)
        try FileManager.default.moveItem(at: moved, to: project)
        let outside = root.appendingPathComponent("keep.txt")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("node_modules/link"), withDestinationURL: outside)
        let current = try await service.scan(roots: [root.path])
        #expect(await service.trim(current.candidates).first?.status == .removed)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
    }
    @Test func boundedScansMarkIncompleteAndCancelledDeletionDoesNothing() async throws {
        let (root, project) = try fixture(["node_modules"]); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<5 { try Data([65]).write(to: project.appendingPathComponent("node_modules/\(i)")) }
        let service = DeveloperProjectTrimmer(sizingLimit: 2)
        let scan = try await service.scan(roots: [root.path], minimumBytes: 0)
        #expect(!scan.isComplete && scan.candidates.first?.sizeComplete == false)
        let limited = try await DeveloperProjectTrimmer(discoveryLimit: 1).scan(roots: [root.path], minimumBytes: 0)
        #expect(!limited.isComplete)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            return await service.trim(scan.candidates)
        }
        task.cancel(); continuation.finish()
        let cancelled = await task.value
        #expect(cancelled.allSatisfy { $0.status == .cancelled })
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("node_modules").path))
    }
}
