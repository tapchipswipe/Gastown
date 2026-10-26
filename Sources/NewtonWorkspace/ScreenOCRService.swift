import AppKit
import Carbon.HIToolbox
import NewtonCore

public enum OCRCaptureState: Sendable, Equatable {
    case stopped, starting, capturing, stopping, paused, blocked(String), failed(String)
    public var description: String {
        switch self {
        case .stopped: "Off"
        case .starting: "Starting"
        case .capturing: "Capturing text · experimental"
        case .stopping: "Stopping"
        case .paused: "Paused · screen locked or sleeping"
        case .blocked(let reason): "Blocked · " + reason
        case .failed(let message): "Failed · " + message
        }
    }
}
@MainActor public protocol ScreenOCRCapturing: AnyObject {
    func start(onState: @escaping @MainActor (OCRCaptureState) -> Void, onEvent: @escaping @MainActor (HistoryEvent) -> Void)
    func stop()
}
private final class OCRNotification {
    let center: NotificationCenter
    let token: NSObjectProtocol
    init(_ center: NotificationCenter, _ token: NSObjectProtocol) { self.center = center; self.token = token }
    deinit { center.removeObserver(token) }
}

/// Owns one sampling loop; stop/suspension invalidates every outstanding callback.
@MainActor public final class ScreenOCRService: ScreenOCRCapturing {
    private let sample: @Sendable () async throws -> HistoryEvent?
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var enabled = false
    private var suspended = Set<String>()
    private var registrations: [OCRNotification] = []
    private var onState: (@MainActor (OCRCaptureState) -> Void)?
    private var onEvent: (@MainActor (HistoryEvent) -> Void)?
    public convenience init() {
        let engine = VisionCaptureEngine()
        self.init(sample: {
            let context = await MainActor.run { () -> (String, Bool) in
                let app = NSWorkspace.shared.frontmostApplication
                let exclusions = UserDefaults.standard.stringArray(forKey: "Newton.captureExcludedBundleIDs") ?? []
                return (app?.localizedName ?? "Unknown app", IsSecureEventInputEnabled() || exclusions.contains(app?.bundleIdentifier ?? ""))
            }
            guard !context.1 else { throw CapturePrivacyBlocked("Secure input or selected excluded app; OCR paused") }
            return try await engine.captureFrame(appName: context.0)?.asHistoryEvent()
        }, observeSystem: true)
    }
    public init(sample: @escaping @Sendable () async throws -> HistoryEvent?, interval: Duration = .seconds(4), observeSystem: Bool = false) {
        self.sample = sample; self.interval = interval
        if observeSystem {
            let workspace = NSWorkspace.shared.notificationCenter
            for (name, reason, paused) in [(NSWorkspace.willSleepNotification, "sleep", true),
                                            (NSWorkspace.didWakeNotification, "sleep", false),
                                            (NSWorkspace.screensDidSleepNotification, "display", true),
                                            (NSWorkspace.screensDidWakeNotification, "display", false)] {
                observe(workspace, name, reason, paused)
            }
            observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), "lock", true)
            observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"), "lock", false)
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ reason: String, _ paused: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.setSuspended(paused, reason: reason) }
        }
        registrations.append(OCRNotification(center, token))
    }
    public func start(onState: @escaping @MainActor (OCRCaptureState) -> Void, onEvent: @escaping @MainActor (HistoryEvent) -> Void) {
        guard !enabled else { return }
        enabled = true; self.onState = onState; self.onEvent = onEvent
        if suspended.isEmpty { launch() } else { onState(.paused) }
    }
    public func stop() {
        generation = UUID(); task?.cancel(); task = nil; enabled = false
        onState?(.stopping); onState?(.stopped); onState = nil; onEvent = nil
    }
    public func setSuspended(_ value: Bool, reason: String) {
        if value { suspended.insert(reason) } else { suspended.remove(reason) }
        guard enabled else { return }
        generation = UUID(); task?.cancel(); task = nil
        if suspended.isEmpty { launch() } else { onState?(.paused) }
    }
    private func launch() {
        generation = UUID(); let id = generation, sample = sample, interval = interval
        onState?(.starting)
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let event = try await sample()
                    guard let self, self.enabled, self.generation == id, self.suspended.isEmpty, !Task.isCancelled else { return }
                    self.onState?(.capturing)
                    if let event, !event.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.onEvent?(event) }
                    try await Task.sleep(for: interval)
                } catch let privacy as CapturePrivacyBlocked {
                    guard let self,self.generation == id,self.enabled,!Task.isCancelled else { return }
                    self.onState?(.blocked(privacy.reason))
                    do { try await Task.sleep(for: interval) } catch { return }
                } catch {
                    guard let self, self.generation == id, self.enabled, !Task.isCancelled else { return }
                    self.enabled = false; self.onState?(.failed(error.localizedDescription))
                    self.onState = nil; self.onEvent = nil; self.task = nil
                    return
                }
            }
        }
    }
}
