import Foundation
import Darwin
import Testing
@testable import NewtonCore

struct StabilizationTests {
    func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @Test func repeatedConcurrentIdeasNeverReplaceNotes() async throws {
        let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for i in 0..<20 { group.addTask { try iCloudIdeaStore.saveIdea(title: String(repeating: "Same / IDEA ", count: 100), detail: "note \(i)", in: dir) } }
            var urls: [URL] = []; for try await url in group { urls.append(url) }; return urls
        }
        #expect(Set(urls).count == 20)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 20)
        for url in urls { #expect(url.lastPathComponent.utf8.count < 200) }
        let unicode = try iCloudIdeaStore.saveIdea(title: String(repeating: "𐐀", count: 400), in: dir)
        #expect(unicode.lastPathComponent.utf8.count <= 100)
        let file = dir.appendingPathComponent("blocked"); try Data().write(to: file)
        #expect(throws: (any Error).self) { try iCloudIdeaStore.saveIdea(title: "x", in: file) }
    }
    @Test func malformedProtobufThrowsAndJournalIdentityIsStable() throws {
        for bytes: [UInt8] in [[0], [8, 128], [10, 255,255,255,255,255,255,255,255,255,1], [11], [8,255,255,255,255,255,255,255,255,255,2], [10,2,1]] {
            #expect(throws: (any Error).self) { try ProtoWireDecoder.decodeFields(from: Data(bytes)) }
        }
        let data = Data([18,5,34,3,97,98,99])
        let first = try TimeAtlasReader.parseData(data, filename: "dir/journal.pb")
        let second = try TimeAtlasReader.parseData(data, filename: "dir/journal.pb")
        #expect(first.first?.id == second.first?.id)
        #expect(throws: (any Error).self) { try TimeAtlasReader.parseData(data, maximumFields: 1) }
        let storeDir = temporary(); try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        try data.write(to: storeDir.appendingPathComponent("good.pb"))
        try Data([10,255]).write(to: storeDir.appendingPathComponent("bad.pb"))
        let report = try TimeAtlasReader.readReport(from: storeDir)
        #expect(report.events.count == 1); #expect(report.diagnostics.count == 1)
        var limits = IntakeLimits(); limits.fileBytes = 2
        #expect(try TimeAtlasReader.readReport(from: storeDir, limits: limits).events.isEmpty)
        limits = IntakeLimits(); limits.files = 0
        #expect(try TimeAtlasReader.readReport(from: storeDir, limits: limits).diagnostics.count == 2)
    }
    @Test func processDrainsBothPipesBoundsOutputAndOwnsCancellation() async throws {
        let runner = ProcessRunner(), dir = temporary()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let flood = try await runner.run("/bin/sh", ["-c", "i=0; while [ $i -lt 6000 ]; do echo abcdefghijklmnopqrstuvwxyz; echo stderr-abcdefghijklmnopqrstuvwxyz >&2; i=$((i+1)); done"], directory: dir, outputLimit: 4096)
        #expect(flood.exitCode == 0); #expect(flood.truncated)
        #expect(flood.stdout.utf8.count <= 4096); #expect(flood.stderr.utf8.count <= 4096)
        await #expect(throws: (any Error).self) { try await runner.run("/missing-newton-executable", [], directory: dir) }
        await #expect(throws: RunnerError.self) { try await runner.run("/bin/sh", ["-c", "trap '' TERM; sleep 30"], directory: dir, timeout: 0.05) }
        let task = Task { try await runner.run("/bin/sh", ["-c", "sleep 30"], directory: dir) }
        try await Task.sleep(for: .milliseconds(30)); task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
    @Test func gitRepositoryAndWorktreeTruth() async throws {
        let dir = temporary(), worktree = temporary(); let runner = ProcessRunner()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: worktree) }
        func git(_ args: [String]) async throws { let result = try await runner.run("/usr/bin/git", args, directory: dir); #expect(result.exitCode == 0) }
        try await git(["init"])
        try await git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-m", "fixture"])
        #expect(await ProjectAtlasScanner.inspectRepo(at: dir).condition == .clean)
        try Data("x".utf8).write(to: dir.appendingPathComponent("untracked"))
        #expect(await ProjectAtlasScanner.inspectRepo(at: dir).condition == .dirty)
        for index in 0..<3000 { try Data().write(to: dir.appendingPathComponent(String(repeating: "x", count: 140) + String(index))) }
        let crowded = await ProjectAtlasScanner.inspectRepo(at: dir)
        #expect(crowded.condition == .dirty)
        try await git(["worktree", "add", "--detach", worktree.path, "HEAD"])
        let project = await ProjectAtlasScanner.inspectRepo(at: worktree)
        #expect(project.condition == .clean); #expect(project.activeBranch == "HEAD")
    }
    @Test func quotaDiscoveryAndTimestampAreBounded() throws {
        let dir = temporary(), sessions = dir.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let line = #"{"timestamp":"2020-01-01T00:00:00Z","rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":9999999999}}}"#
        try Data(line.utf8).write(to: sessions.appendingPathComponent("x.jsonl"))
        let snapshot = CodexQuotaReader.readSnapshot(codexHome: dir)
        #expect(snapshot.description().contains("Stale"))
        #expect(snapshot.quota?.observedAt.timeIntervalSince1970 == 1577836800)
        #expect(CodexQuotaReader.readSnapshot(codexHome: dir, maximumEntries: 0).diagnostic.contains("limit"))
        #expect(CodexQuotaReader.readQuotaFromRollout(sessions.appendingPathComponent("x.jsonl"), maximumBytes: 5) == nil)
        #expect(CodexQuotaReader.parseRateLimits(from: Data(line.replacingOccurrences(of: ":12,", with: ":112,").utf8)) == nil)
    }
}

struct IntakeAcceptanceTests {
    @Test func repeatedJournalImportsAddNothingAndLimitsAreExplicit() async throws {
        let store = try EventStore(path: ":memory:")
        let data = Data([18,5,34,3,97,98,99])
        let first = try TimeAtlasReader.parseData(data, filename: "source.pb")
        #expect(try await store.append(first) == 1)
        #expect(try await store.append(TimeAtlasReader.parseData(data, filename: "source.pb")) == 0)
        #expect(try await store.count() == 1)
        #expect(throws: (any Error).self) { try TimeAtlasReader.parseData(Data(repeating: 0, count: 4 * 1024 * 1024 + 1)) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("a.pb")); try data.write(to: dir.appendingPathComponent("b.pb"))
        var limits = IntakeLimits(); limits.totalBytes = data.count
        let partial = try TimeAtlasReader.readReport(from: dir, limits: limits)
        #expect(partial.events.count == 1); #expect(partial.diagnostics.first?.contains("total byte limit") == true)
        limits.directoryEntries = 0
        #expect(try TimeAtlasReader.readReport(from: dir, limits: limits).diagnostics.first?.contains("unexamined") == true)
        #expect(try TimeAtlasReader.readReport(from: dir.appendingPathComponent("missing")).diagnostics.first?.contains("unavailable") == true)
    }
}

struct QuotaValidityTests {
    @Test func invalidMissingExpiredAndStaleQuotaAreExplicit() {
        let now = Date()
        #expect(QuotaSnapshot(quota: nil, diagnostic: "Missing").description(at: now) == "Missing")
        let expired = CodexQuota(planType: "fixture", primary: QuotaWindow(usedPercent: 1, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1)), observedAt: now)
        #expect(QuotaSnapshot(quota: expired, diagnostic: "fixture").description(at: now).contains("Expired"))
        let future = CodexQuota(planType: "fixture", primary: QuotaWindow(usedPercent: 1, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600)), observedAt: now.addingTimeInterval(1000))
        #expect(QuotaSnapshot(quota: future, diagnostic: "fixture").description(at: now).contains("Invalid"))
        for value in ["true", "-1", "101", "1e300"] {
            let text = "{\"primary\":{\"used_percent\":\(value),\"window_minutes\":300,\"resets_at\":1999999999}}"
            #expect(CodexQuotaReader.parseRateLimits(from: Data(text.utf8)) == nil)
        }
    }
}

struct IntakeDiscoveryTests {
    @Test func unreadableSubdirectoryIsReportedRatherThanCompleteIntake() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let blocked = root.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Data("# fixture\nbody".utf8).write(to: root.appendingPathComponent("valid.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        let report = try iCloudIdeaStore.readReport(from: root)
        #expect(report.events.count == 1)
        #expect(!report.diagnostics.isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ProcessGroupAcceptanceTests {
    @Test func cancellationKillsDescendantEvenAfterLeaderAndPipesExit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("child.pid"), parentMarker = root.appendingPathComponent("parent.pid")
        let child = "import os,signal,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); open(sys.argv[1],'w').write(str(os.getpid())); time.sleep(30)"
        let parent = "import os,signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_DFL); open(sys.argv[3],'w').write(str(os.getpid())); subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(30)"
        let executable = try await ProcessRunner().run("/usr/bin/python3", ["-c", "import sys; print(sys.executable)"], directory: root).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let operation = Task { try await ProcessRunner().run(executable, ["-c", parent, child, marker.path, parentMarker.path], directory: root) }
        defer { operation.cancel() }
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        let parentPID = try #require(Int32(String(contentsOf: parentMarker, encoding: .utf8)))
        let group = getpgid(pid)
        #expect(group == parentPID)
        defer { if getpgid(pid) == group { kill(-group, SIGKILL) } }
        operation.cancel()
        await #expect(throws: (any Error).self) { try await operation.value }
        // A zombie is terminated and awaiting launchd reaping; a running/sleeping child is a leak.
        let state = try await ProcessRunner().run("/bin/ps", ["-p", String(pid), "-o", "stat="], directory: root)
        #expect(state.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.stdout.contains("Z"))
    }
}
