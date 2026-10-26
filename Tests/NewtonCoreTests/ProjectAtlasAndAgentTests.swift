import Testing
import Foundation
@testable import NewtonCore

struct ProjectAtlasAndAgentTests {

    @Test func nonexistentRepositoryIsUnavailable() async {
        let project = await ProjectAtlasScanner.inspectRepo(at: URL(fileURLWithPath: "/nonexistent-newton-fixture"))
        #expect(project.condition == .unavailable)
        #expect(project.lastCommitDate == nil)
    }

    @Test func testAgentTaskStatusInitialization() {
        let status = AgentTaskStatus(
            isRunning: false,
            taskTitle: "Add Test Feature",
            latestOutput: "All tests green",
            exitCode: 0,
            passedTests: true
        )

        #expect(status.isRunning == false)
        #expect(status.taskTitle == "Add Test Feature")
        #expect(status.exitCode == 0)
        #expect(status.passedTests == true)
    }
}
