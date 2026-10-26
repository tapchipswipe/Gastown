import Foundation

public enum ActionType: String, Sendable, Codable, Equatable {
    case click
    case doubleClick
    case rightClick
    case keypress
    case appSwitch
    case textInput
}

public struct CapturedAction: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let type: ActionType
    public let appName: String
    public let windowTitle: String
    public let coordinateX: Double?
    public let coordinateY: Double?
    public let details: String

    public init(id: String = UUID().uuidString,
                timestamp: Date = Date(),
                type: ActionType,
                appName: String,
                windowTitle: String = "",
                coordinateX: Double? = nil,
                coordinateY: Double? = nil,
                details: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.appName = appName
        self.windowTitle = windowTitle
        self.coordinateX = coordinateX
        self.coordinateY = coordinateY
        self.details = details
    }
}

public struct WorkflowSession: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let startedAt: Date
    public var endedAt: Date?
    public var actions: [CapturedAction]

    public init(id: String = UUID().uuidString,
                title: String,
                startedAt: Date = Date(),
                endedAt: Date? = nil,
                actions: [CapturedAction] = []) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.actions = actions
    }
}

/// Pure session budget, shared by native capture and disposable regression fixtures.
public struct WorkflowCaptureBuffer: Sendable {
    public private(set) var session: WorkflowSession
    public let maximumActions: Int
    public let maximumSeconds: TimeInterval
    public init(title: String, startedAt: Date = Date(), maximumActions: Int = 10_000, maximumSeconds: TimeInterval = 3600) {
        session = WorkflowSession(title: title, startedAt: startedAt)
        self.maximumActions = maximumActions; self.maximumSeconds = maximumSeconds
    }
    public mutating func append(_ action: CapturedAction, now: Date = Date()) -> Bool {
        guard session.actions.count < maximumActions, now.timeIntervalSince(session.startedAt) < maximumSeconds else { return false }
        // The second mouse-down replaces its first single click, so replay does not triple-click.
        if action.type == .doubleClick, let last = session.actions.last, last.type == .click,
           last.appName == action.appName, last.coordinateX == action.coordinateX, last.coordinateY == action.coordinateY,
           action.timestamp.timeIntervalSince(last.timestamp) < 1 { session.actions.removeLast() }
        session.actions.append(action)
        return session.actions.count < maximumActions
    }
}
