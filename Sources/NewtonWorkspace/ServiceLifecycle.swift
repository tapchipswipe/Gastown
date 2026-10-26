import Foundation
import AppKit

public enum ServicePhase: String, Sendable, Codable { case disabled, starting, running, paused, blocked, failed }
public struct ServiceLifecycle: Sendable, Equatable {
    public var phase: ServicePhase
    public var reason: String
    public var lastSuccessfulActivity: Date?
    public init(_ phase: ServicePhase, reason: String, lastSuccessfulActivity: Date? = nil) {
        self.phase = phase; self.reason = reason; self.lastSuccessfulActivity = lastSuccessfulActivity
    }
}

private final class LifecycleRegistration {
    let center: NotificationCenter
    let token: NSObjectProtocol
    init(_ center: NotificationCenter, _ token: NSObjectProtocol) { self.center = center; self.token = token }
    deinit { center.removeObserver(token) }
}
@MainActor final class WorkspaceSystemLifecycle {
    private var observations: [LifecycleRegistration] = []
    init(change: @escaping @MainActor (Bool, String) -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for (center, name, suspended, reason) in [
            (workspace, NSWorkspace.willSleepNotification, true, "sleep"),
            (workspace, NSWorkspace.didWakeNotification, false, "sleep"),
            (distributed, Notification.Name("com.apple.screenIsLocked"), true, "lock"),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), false, "lock")
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { change(suspended, reason) }
            }
            observations.append(LifecycleRegistration(center, token))
        }
    }
}
