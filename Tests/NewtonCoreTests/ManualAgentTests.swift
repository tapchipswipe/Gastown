import Foundation
import Testing
@testable import NewtonCore

@Suite(.timeLimit(.minutes(1)))
struct ManualAgentTests {
    func fixture(test: String = "exit 0", agent: String = "echo fake-agent") async throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("repo"), executable = root.appendingPathComponent("fake-agent")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try ("#!/bin/sh\n" + agent + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try ("#!/bin/sh\n" + test + "\n").write(to: repo.appendingPathComponent("test.sh"), atomically: true, encoding: .utf8)
        for args in [["init"], ["add", "."], ["-c", "user.name=Fixture", "-c", "user.email=f@example.invalid", "commit", "-m", "fixture"]] {
            let result = try await ProcessRunner().run("/usr/bin/git", args, directory: repo); #expect(result.exitCode == 0)
        }
        return (root, repo, executable)
    }
    @Test func manualRunIsIsolatedAndKeepsChangesForReview() async throws {
        let (root, repo, exe) = try await fixture(agent: "echo review > agent-change.txt; echo fixture")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("uncommitted".utf8).write(to: repo.appendingPathComponent("private-draft.txt"))
        let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { _ in exe.path })
        let result = await dispatcher.run(id: UUID(), task: PromptTask(title: "fixture", objective: "test"), repository: repo, unattended: false) { _ in }
        #expect(result.phase == .completed); #expect(result.passedTests == true)
        let worktree = try #require(result.worktreePath)
        #expect(FileManager.default.fileExists(atPath: worktree + "/agent-change.txt"))
        #expect(!FileManager.default.fileExists(atPath: worktree + "/private-draft.txt"))
        #expect(!FileManager.default.fileExists(atPath: repo.path + "/agent-change.txt"))
        #expect(result.baseRevision?.count == 40)
    }
    @Test func unchangedWorktreesAreRemovedAndUnattendedAlwaysRejected() async throws {
        let (root, repo, exe) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { _ in exe.path })
        let task = PromptTask(title: "fixture", objective: "test")
        let denied = await dispatcher.run(id: UUID(), task: task, repository: repo, unattended: true) { _ in }
        #expect(denied.phase == .failed); #expect(denied.latestOutput.contains("disabled"))
        let result = await dispatcher.run(id: UUID(), task: task, repository: repo, unattended: false) { _ in }
        #expect(result.phase == .completed)
        #expect(!FileManager.default.fileExists(atPath: try #require(result.worktreePath)))
    }
    @Test func overlappingRunsAreRejectedAndVerificationCancellationIsOwned() async throws {
        let (root, repo, exe) = try await fixture(test: "sleep 30"); defer { try? FileManager.default.removeItem(at: root) }
        let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { _ in exe.path })
        let id = UUID(), task = PromptTask(title: "fixture", objective: "test")
        let (stream, continuation) = AsyncStream<AgentTaskStatus>.makeStream()
        let run = Task {
            let result = await dispatcher.run(id: id, task: task, repository: repo, unattended: false) { continuation.yield($0) }
            continuation.finish(); return result
        }
        for await state in stream {
            if state.phase == .verifying {
                let overlap = await dispatcher.run(id: UUID(), task: task, repository: repo, unattended: false) { _ in }
                #expect(overlap.phase == .failed); #expect(overlap.latestOutput.contains("Another"))
                await dispatcher.cancel(id: id); break
            }
        }
        let result = await run.value
        #expect(result.phase == .cancelled); #expect(result.passedTests != true)
        #expect(FileManager.default.fileExists(atPath: try #require(result.worktreePath)))
    }
    @Test func failedLaunchNonzeroTestsTimeoutAndOutputCannotReportSuccess() async throws {
        let (root, repo, exe) = try await fixture(test: "exit 7", agent: "i=0; while [ $i -lt 40000 ]; do echo abcdefghijklmnopqrstuvwxyzabcdef; i=$((i+1)); done")
        defer { try? FileManager.default.removeItem(at: root) }
        let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { _ in exe.path })
        let task = PromptTask(title: "fixture", objective: "test")
        let failed = await dispatcher.run(id: UUID(), task: task, repository: repo, unattended: false) { _ in }
        #expect(failed.phase == .failed); #expect(failed.exitCode == 7)
        #expect(failed.truncated); #expect(failed.latestOutput.utf8.count <= 1_048_576)
        let missing = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { _ in "/missing-newton-fixture" })
        let launch = await missing.run(id: UUID(), task: task, repository: repo, unattended: false) { _ in }
        #expect(launch.phase == .failed); #expect(launch.passedTests != true)
        try "#!/bin/sh\necho timeout-evidence\nsleep 30\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        let timeout = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), agentTimeout: 0.1, resolveExecutable: { _ in exe.path })
        let expired = await timeout.run(id: UUID(), task: task, repository: repo, unattended: false) { _ in }
        #expect(expired.phase == .failed); #expect(expired.passedTests != true)
        #expect(expired.latestOutput.contains("timeout-evidence"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("worktrees/" + expired.runID.uuidString + ".json").path))
    }
    @Test func oversizedPromptKeepsMandatoryRequirements() {
        let huge = String(repeating: "雪", count: 30_000)
        let prompt = PromptGenerator.generatePrompt(for: PromptTask(title: huge, objective: huge, targetFiles: [huge], fileSnippets: ["x": huge], architecturalContext: huge))
        #expect(prompt.count <= 14_000)
        #expect(prompt.contains("./test.sh")); #expect(prompt.contains("Never merge, push"))
        #expect(prompt.contains("off by default"))
    }
    @Test func selectedProvidersUseExactArgumentsAndCommittedBoundedContext() async throws {
        let (root, repo, exe) = try await fixture(agent: "printf 'ARG:%s\\nPROMPT:%s\\nCOUNT:%s\\n' \"$1\" \"$2\" \"$#\"")
        defer { try? FileManager.default.removeItem(at: root) }
        try "COMMITTED_NEWTON".write(to: repo.appendingPathComponent("newton.md"), atomically: true, encoding: .utf8)
        try "COMMITTED_MEMORY".write(to: repo.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        for args in [["add", "."], ["-c", "user.name=Fixture", "-c", "user.email=f@example.invalid", "commit", "-m", "context"]] {
            #expect(try await ProcessRunner().run("/usr/bin/git", args, directory: repo).exitCode == 0)
        }
        try "UNCOMMITTED_SECRET".write(to: repo.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        for provider in [AIModelProvider.codex, .gemini] {
            let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"), resolveExecutable: { selected in
                guard selected == provider else { throw StoreError(message: "wrong provider resolved") }
                return exe.path
            })
            let result = await dispatcher.run(id: UUID(), task: PromptTask(title: "fixture", objective: "test"), repository: repo, provider: provider) { _ in }
            #expect(result.phase == .completed)
            #expect(result.latestOutput.contains("ARG:" + (provider == .codex ? "exec" : "-p")))
            #expect(result.latestOutput.contains("COUNT:2"))
            #expect(result.latestOutput.contains("COMMITTED_NEWTON"))
            #expect(result.latestOutput.contains("COMMITTED_MEMORY"))
            #expect(result.latestOutput.contains("UNCOMMITTED_SECRET") == false)
            #expect(result.latestOutput.contains(PromptGenerator.mandatoryInstructions))
        }
        let disabled = AgentDispatcher(resolveExecutable: { _ in throw StoreError(message: "must not resolve") })
        let dual = await disabled.run(id: UUID(), task: PromptTask(title: "x", objective: "x"), repository: repo, provider: .dualOrchestrated) { _ in }
        #expect(dual.phase == .failed && dual.latestOutput.contains("unavailable"))
    }
    @Test func contextFilesAreIndividuallyBoundedAndBothIncludedWithinPromptBudget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try String(repeating: "A", count: 65_536).write(to: root.appendingPathComponent("newton.md"), atomically: true, encoding: .utf8)
        try String(repeating: "B", count: 65_536).write(to: root.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        let context = PromptGenerator.loadProjectContext(from: root)
        #expect(context.count <= 6000)
        #expect(context.contains("AAAA") && context.contains("BBBB"))
        let prompt = PromptGenerator.generatePrompt(for: PromptTask(title: "x", objective: String(repeating: "x", count: 100_000), architecturalContext: context))
        #expect(prompt.count <= 14_000)
        #expect(prompt.contains("AAAA") && prompt.contains("BBBB"))
        #expect(prompt.contains(PromptGenerator.mandatoryInstructions))
        try Data(repeating: 65, count: 65_537).write(to: root.appendingPathComponent("newton.md"))
        #expect(PromptGenerator.loadProjectContext(from: root).contains("newton.md unavailable"))
    }
}
