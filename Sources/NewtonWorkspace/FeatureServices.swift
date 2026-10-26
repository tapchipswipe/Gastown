import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import NewtonCore

@MainActor public protocol ActivityMonitoring: AnyObject {
    var onCoverage: (@MainActor (ServicePhase,String) -> Void)? { get set }
    func start(onEvent: @escaping @MainActor (HistoryEvent) -> Void)
    func stop()
}
public extension ActivityMonitoring {
    var onCoverage: (@MainActor (ServicePhase,String) -> Void)? { get { nil } set {} }
}
@MainActor public protocol WakePreventing: AnyObject {
    func start() throws
    func stop() throws
}

// Registration owns removal even if its service is released without an explicit stop.
private final class NotificationRegistration {
    let center: NotificationCenter
    let token: NSObjectProtocol
    init(center: NotificationCenter, token: NSObjectProtocol) { self.center = center; self.token = token }
    deinit { center.removeObserver(token) }
}

@MainActor public final class ActivityService: ActivityMonitoring {
    public var onCoverage: (@MainActor (ServicePhase,String) -> Void)?
    private var registration: NotificationRegistration?
    private let center: NotificationCenter
    private let secureInput: @MainActor () -> Bool
    private let frontmost: @MainActor () -> NSRunningApplication?
    private var onEvent: (@MainActor (HistoryEvent) -> Void)?
    private var generation = UUID()
    public init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                frontmost: @escaping @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
                secureInput: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() }) {
        self.center = center; self.frontmost = frontmost; self.secureInput = secureInput
    }
    public func start(onEvent: @escaping @MainActor (HistoryEvent) -> Void) {
        guard registration == nil else { return }
        self.onEvent = onEvent
        generation = UUID(); let currentGeneration = generation
        let observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let name = app.localizedName ?? "Unknown app", bundle = app.bundleIdentifier ?? ""
            let time = Date()
            Task { @MainActor [weak self] in
                guard let self,self.registration != nil,self.generation == currentGeneration else { return }
                guard !self.secureInput() else { self.onCoverage?(.blocked,"Secure input active"); return }
                self.onCoverage?(.running,"App activation source available")
                self.onEvent?(HistoryEvent(timestamp: time, source: "Activity", title: name, detail: bundle))
            }
        }
        registration = NotificationRegistration(center: center, token: observer)
        onCoverage?(secureInput() ? .blocked : .running,secureInput() ? "Secure input active" : "App activation source available")
        if !secureInput(), let app = frontmost() {
            onEvent(HistoryEvent(source: "Activity", title: app.localizedName ?? "Unknown app", detail: app.bundleIdentifier ?? ""))
        }
    }
    public func stop() {
        generation = UUID()
        registration = nil; onEvent = nil
    }
}

private final class PowerAssertion {
    private var id: IOPMAssertionID = 0
    init() throws {
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Newton Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { throw StoreError(message: "Could not create a keep-awake assertion (\(result)).") }
    }
    func release() throws {
        guard id != 0 else { return }
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw StoreError(message: "Could not release keep awake (\(result)).") }
        id = 0
    }
    deinit { if id != 0 { IOPMAssertionRelease(id) } }
}
@MainActor public final class KeepAwakeService: WakePreventing {
    private var assertion: PowerAssertion?
    public init() {}
    public func start() throws { if assertion == nil { assertion = try PowerAssertion() } }
    public func stop() throws { try assertion?.release(); assertion = nil }
}
