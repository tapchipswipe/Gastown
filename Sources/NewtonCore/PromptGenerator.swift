import Foundation

public struct PromptTask: Sendable {
    public let title: String
    public let objective: String
    public let targetFiles: [String]
    public let fileSnippets: [String: String]
    public let architecturalContext: String

    public init(title: String,
                objective: String,
                targetFiles: [String] = [],
                fileSnippets: [String: String] = [:],
                architecturalContext: String = "") {
        self.title = title
        self.objective = objective
        self.targetFiles = targetFiles
        self.fileSnippets = fileSnippets
        self.architecturalContext = architecturalContext
    }
}

public struct PromptGenerator: Sendable {
    public static let maxPromptCharacters = 14_000 // Character budget, not a token guarantee.
    public static let mandatoryInstructions = """
## Execution Instructions
1. Implement the requested changes with zero extraneous dependencies.
2. Comply strictly with Swift 6 Sendable and concurrency rules.
3. New capabilities stay off by default; preserve saved capability selections. Keep collection bounded, cancellable and visible.
4. Verify changes locally by running `./test.sh` before reporting success.
5. Work only in the dedicated checkout. Never merge, push, enable unattended jobs or inspect private sessions.
"""
    public static func generatePrompt(for task: PromptTask) -> String {
        let references: [String] = task.fileSnippets.sorted(by: { $0.key < $1.key }).prefix(100).map { path, text in
            String(path.prefix(500)) + "\n" + String(text.prefix(3000))
        }
        let files = task.targetFiles.prefix(100).joined(separator: "\n")
        let sections: [String] = [
            "# TASK: " + String(task.title.prefix(500)),
            "## Objective\n" + String(task.objective.prefix(3000)),
            "## Architectural Constraints & Context\n" + String(task.architecturalContext.prefix(6000)),
            "## Target Files\n" + String(files.prefix(1000)),
            "## Code References\n" + references.joined(separator: "\n")
        ]
        let warning = "\n[Optional context may be truncated; character budget, not token count.]"
        let budget = maxPromptCharacters - mandatoryInstructions.count - warning.count - 1
        return mandatoryInstructions + "\n" + String(sections.joined(separator: "\n").prefix(budget)) + warning
    }

    /// Read both committed-checkout context files, without following symlinks or unbounded reads.
    public static func loadProjectContext(from repoRoot: URL) -> String {
        var parts: [String] = []
        for name in ["newton.md", "MEMORY.md"] {
            let url = repoRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try BoundedIntake.read(url, maximum: 65_536)
                guard let text = String(data: data, encoding: .utf8) else { throw StoreError(message: "Invalid UTF-8") }
                parts.append("## " + name + "\n" + String(text.prefix(2950)))
            } catch { parts.append("## " + name + " unavailable: " + String(error.localizedDescription.prefix(200))) }
        }
        return String(parts.joined(separator: "\n").prefix(6000))
    }

    /// Constructs a PromptTask with automatic architectural anchoring from the local project.
    public static func makeContextualTask(
        title: String,
        objective: String,
        repoRoot: URL? = nil,
        targetFiles: [String] = []
    ) -> PromptTask {
        let context = repoRoot.map { loadProjectContext(from: $0) } ?? ""
        return PromptTask(
            title: title,
            objective: objective,
            targetFiles: targetFiles,
            fileSnippets: [:],
            architecturalContext: context
        )
    }
}
