import Foundation

public enum AIModelProvider: String, Sendable, Codable, CaseIterable, Identifiable {
    case codex = "Codex"
    case gemini = "Gemini"
    case dualOrchestrated = "Dual (Codex + Gemini)"

    public var id: String { rawValue }

    public var executableName: String {
        switch self {
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .dualOrchestrated: return "codex"
        }
    }

    public var description: String {
        switch self {
        case .codex: return "OpenAI Codex CLI (5h rolling quota)"
        case .gemini: return "Google Gemini / Antigravity CLI"
        case .dualOrchestrated: return "Unavailable: dual orchestration is not implemented. Select one provider."
        }
    }
}

public struct AIJobRequest: Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let targetRepo: URL
    public let provider: AIModelProvider
    public let queuedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        targetRepo: URL,
        provider: AIModelProvider = .codex,
        queuedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.targetRepo = targetRepo
        self.provider = provider
        self.queuedAt = queuedAt
    }
}

public struct DualAIEngine: Sendable {
    /// Recommends the optimal AI provider based on task keywords and complexity.
    public static func recommendProvider(for taskDescription: String) -> AIModelProvider {
        let lower = taskDescription.lowercased()
        if lower.contains("architecture") || lower.contains("audit") || lower.contains("refactor") || lower.contains("concurrency") || lower.contains("swift 6") {
            return .gemini
        } else if lower.contains("ui") || lower.contains("swiftui") || lower.contains("view") || lower.contains("cli") {
            return .codex
        }
        return .codex
    }
}
