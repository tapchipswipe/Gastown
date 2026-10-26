import Foundation

public struct HistoryEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let timestamp: Date
    public let source: String
    public let title: String
    public let detail: String

    public init(id: String = UUID().uuidString, timestamp: Date = Date(),
                source: String, title: String, detail: String = "") {
        self.id = id; self.timestamp = timestamp; self.source = source
        self.title = title; self.detail = detail
    }
}

public enum NewtonFeature: String, CaseIterable, Identifiable, Sendable {
    case activity, keepAwake, screenpipe, screenOCR, mailFinance, dailyReports, projectContext, overnightAgents
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mailFinance: "Read-only Mail receipts"
        case .dailyReports: "Automatic daily summaries"
        case .projectContext: "Automatic repository context"
        case .overnightAgents: "Overnight coding queue"
        case .screenOCR: "Screen OCR — Experimental"
        case .activity: "Activity history"
        case .keepAwake: "Keep awake"
        case .screenpipe: "Screenpipe connection"
        }
    }
    public var symbol: String {
        switch self {
        case .mailFinance: "envelope"
        case .dailyReports: "doc.text"
        case .projectContext: "folder"
        case .overnightAgents: "moon"
        case .screenOCR: "text.viewfinder"
        case .activity: "clock.arrow.circlepath"
        case .keepAwake: "sun.max"
        case .screenpipe: "rectangle.connected.to.line.below"
        }
    }
    public var explanation: String {
        switch self {
        case .mailFinance: "Read Apple Mail receipts from the last 12 months, without changing messages. Requires Automation. Incomplete and ambiguous evidence stays visible."
        case .dailyReports: "Save a source-linked local summary at 08:15, catch up after wake and update changed evidence."
        case .projectContext: "Discover local repositories, cache unchanged context and refresh every 30 minutes."
        case .overnightAgents: "Opt in to trusted Newton backlog work only after rollout acceptance. Night/power/idle/thermal/quota gates apply; review changes manually."
        case .screenOCR: "Recognize main-display text every four seconds. Text stays local; no screenshots saved. Pauses on lock/sleep. Live validation pending."
        case .activity: "Save app switches locally. No screenshots, keystrokes, or audio."
        case .keepAwake: "Prevent idle system sleep while enabled. Closing the lid still works normally."
        case .screenpipe: "Search a separately running Screenpipe service on this Mac, only when you ask."
        }
    }
}
