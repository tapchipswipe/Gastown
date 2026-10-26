import Foundation

public struct StandupReport: Sendable, Equatable {
    public let yesterday: [String]
    public let today: [String]
    public let blockers: [String]
    public let fullMarkdown: String
    public let generatedAt: Date

    public init(yesterday: [String], today: [String], blockers: [String], fullMarkdown: String, generatedAt: Date = Date()) {
        self.yesterday = yesterday
        self.today = today
        self.blockers = blockers
        self.fullMarkdown = fullMarkdown
        self.generatedAt = generatedAt
    }
}

public struct SOPStep: Identifiable, Sendable, Equatable {
    public let id: Int
    public let action: String
    public let targetApp: String
    public let details: String

    public init(id: Int, action: String, targetApp: String, details: String) {
        self.id = id
        self.action = action
        self.targetApp = targetApp
        self.details = details
    }
}

public struct SOPReport: Sendable, Equatable {
    public let title: String
    public let steps: [SOPStep]
    public let markdownSOP: String
    public let generatedAt: Date

    public init(title: String, steps: [SOPStep], markdownSOP: String, generatedAt: Date = Date()) {
        self.title = title
        self.steps = steps
        self.markdownSOP = markdownSOP
        self.generatedAt = generatedAt
    }
}

public struct MissedToDosReport: Sendable, Equatable {
    public let likelyMissed: [String]
    public let waitingOnMe: [String]
    public let quickWins: [String]
    public let fullMarkdown: String
    public let generatedAt: Date

    public init(likelyMissed: [String], waitingOnMe: [String], quickWins: [String], fullMarkdown: String, generatedAt: Date = Date()) {
        self.likelyMissed = likelyMissed
        self.waitingOnMe = waitingOnMe
        self.quickWins = quickWins
        self.fullMarkdown = fullMarkdown
        self.generatedAt = generatedAt
    }
}

public struct MeetingDigestReport: Sendable, Equatable {
    public let title: String
    public let decisions: [String]
    public let actionItems: [String]
    public let summary: String
    public let fullMarkdown: String
    public let generatedAt: Date

    public init(title: String, decisions: [String], actionItems: [String], summary: String, fullMarkdown: String, generatedAt: Date = Date()) {
        self.title = title
        self.decisions = decisions
        self.actionItems = actionItems
        self.summary = summary
        self.fullMarkdown = fullMarkdown
        self.generatedAt = generatedAt
    }
}

/// Deterministic extraction: observations are evidence, never proof of completion or intent.
public enum PipeAutomationEngine: Sendable {
    private static func anchor(_ event: HistoryEvent) -> String {
        "observation-" + event.id.utf8.map { String(format: "%02x", $0) }.joined()
    }
    private static func cited(_ event: HistoryEvent) -> String {
        "\(event.title) ([observation](#\(anchor(event))))"
    }
    private static func sources(_ events: [HistoryEvent]) -> String {
        var seen = Set<String>()
        return "\n## Contributing observations\n" + events.filter { seen.insert($0.id).inserted }.map {
            "\n<a id=\"\(anchor($0))\"></a>\n**\($0.id)** · \($0.timestamp.ISO8601Format()) · \($0.source)\n\n\($0.title)\n\n\($0.detail)\n"
        }.joined()
    }
    public static func synthesizeStandup(events: [HistoryEvent], projects: [TrackedProject]) -> StandupReport {
        let ordered = events.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
        let observations = ordered.prefix(100).map(cited)
        let errors = ordered.filter {
            let text = ($0.title + " " + $0.detail).lowercased()
            return text.contains("error") || text.contains("failed") || text.contains("fatal")
        }.prefix(10).map(cited)
        let insufficient = ["Insufficient evidence"]
        let observed = observations.isEmpty ? insufficient : observations
        let blockers = errors.isEmpty ? insufficient : errors
        let repositories = projects.prefix(20).map {
            let url = URL(fileURLWithPath: $0.path).absoluteString
            return "- Recently inspected repository: [\($0.name)](\(url)), branch \($0.activeBranch). Active project association unavailable."
        }.joined(separator: "\n")
        let md = "# 📋 Daily Engineering Standup\n\nObservation summary; completion, today's intentions and unresolved blockers require confirmation. Input: \(events.count) saved observations. Display limited to 100 observations and 10 error mentions; capture gaps unknown.\n\n## Recorded observations\n" + observed.map { "- " + $0 }.joined(separator: "\n") + "\n\n## Today\nInsufficient evidence\n\n## Possible error mentions\n" + blockers.map { "- " + $0 }.joined(separator: "\n") + "\n\n" + repositories + sources(Array(ordered.prefix(100)) + ordered.filter { errors.contains(cited($0)) })
        return StandupReport(yesterday: observed, today: insufficient, blockers: blockers, fullMarkdown: md)
    }
    public static func generateSOP(title: String, recordedActions: [HistoryEvent]) -> SOPReport {
        let selected = Array(recordedActions.prefix(500))
        let steps = selected.enumerated().map { index, event in
            SOPStep(id: index + 1, action: cited(event), targetApp: event.title, details: event.detail)
        }
        let md = "# Recorded procedure: \(title)\n\nObserved sequence; steps have not been replayed or verified.\n\n" + (steps.isEmpty ? "Insufficient evidence" : steps.map { "\($0.id). \($0.action)" }.joined(separator: "\n")) + sources(selected)
        return SOPReport(title: title, steps: steps, markdownSOP: md)
    }
    public static func synthesizeMissedToDos(events: [HistoryEvent]) -> MissedToDosReport {
        var commitments: [HistoryEvent] = [], requests: [HistoryEvent] = [], todos: [HistoryEvent] = []
        for event in events {
            let text = (event.title + " " + event.detail).lowercased()
            if text.contains("todo") || text.contains("fixme") { todos.append(event) }
            else if text.contains("can you") || text.contains("please") || text.contains("waiting on") { requests.append(event) }
            else if text.contains("i will") || text.contains("i'll") || text.contains("deadline") { commitments.append(event) }
        }
        commitments = Array(commitments.prefix(50)); requests = Array(requests.prefix(50)); todos = Array(todos.prefix(50))
        func section(_ title: String, _ items: [HistoryEvent]) -> String {
            "\n## \(title)\n" + (items.isEmpty ? "Insufficient evidence\n" : items.map { "- \(cited($0))\n" }.joined())
        }
        let md = "# ✅ Missed To-Dos & Commitments Radar\n\nCandidates only. Assignment, due date, completion and time required are unverified.\n" + section("Commitment mentions", commitments) + section("Request mentions", requests) + section("To-do mentions", todos) + sources(commitments + requests + todos)
        return MissedToDosReport(likelyMissed: commitments.map(cited), waitingOnMe: requests.map(cited), quickWins: todos.map(cited), fullMarkdown: md)
    }
    public static func synthesizeMeetingDigest(title: String, notes: String) -> MeetingDigestReport {
        let lines = notes.components(separatedBy: "\n")
        var decisions: [String] = [], actions: [String] = [], evidence: [String] = []
        for (index, line) in lines.enumerated() {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            let citation = "\(text) ([note line \(index + 1)](#note-\(index + 1)))"
            if ["decided", "agreed", "approved", "decision:"].contains(where: lower.contains) { decisions.append(citation) }
            else if ["action item", "todo", "will ", "assigned to"].contains(where: lower.contains) { actions.append(citation) }
            else { continue }
            evidence.append("<a id=\"note-\(index + 1)\"></a>\nLine \(index + 1): \(text)")
        }
        let summary = decisions.isEmpty && actions.isEmpty ? "Insufficient evidence" : "\(decisions.count) decision mention(s), \(actions.count) action candidate(s) in supplied notes. Completion and speaker identity unverified."
        let md = "# 🤝 Meeting Digest: \(title)\n\n\(summary)\n\n## Decision mentions\n" + decisions.map { "- " + $0 }.joined(separator: "\n") + "\n\n## Action candidates\n" + actions.map { "- " + $0 }.joined(separator: "\n") + "\n\n## Supplied note evidence\n" + evidence.joined(separator: "\n\n")
        return MeetingDigestReport(title: title, decisions: decisions, actionItems: actions, summary: summary, fullMarkdown: md)
    }
}
