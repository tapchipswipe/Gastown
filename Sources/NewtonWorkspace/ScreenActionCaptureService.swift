import AppKit
import Foundation
import NewtonCore

@MainActor
public protocol WorkflowRecording: AnyObject, Sendable {
    func start(sessionTitle: String, onLimit: @escaping @MainActor (WorkflowSession) -> Void) throws
    func stop() -> WorkflowSession?
    var isRecording: Bool { get }
}

@MainActor
public protocol WorkflowEventSource: AnyObject, Sendable {
    func start(onAction: @escaping @MainActor (CapturedAction) -> Void) throws
    func stop()
}

@MainActor
public final class NativeWorkflowEventSource: WorkflowEventSource {
    private var appObserver: Any?
    private var eventMonitor: Any?
    public init() {}
    public func start(onAction: @escaping @MainActor (CapturedAction) -> Void) throws {
        stop()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? "Unknown", bid = app?.bundleIdentifier ?? ""
            Task { @MainActor in onAction(CapturedAction(type: .appSwitch, appName: name, details: bid)) }
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            // Quartz global coordinates match the generated CGEvent replay, including other displays.
            guard let point = event.cgEvent?.location else { return }
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
            let kind: ActionType = event.type == .rightMouseDown ? .rightClick : (event.clickCount == 2 ? .doubleClick : .click)
            Task { @MainActor in onAction(CapturedAction(type: kind, appName: front, coordinateX: point.x, coordinateY: point.y)) }
        }
        guard eventMonitor != nil else { stop(); throw StoreError(message: "Cannot install workflow mouse monitor. Check macOS permissions.") }
        if let front = NSWorkspace.shared.frontmostApplication {
            onAction(CapturedAction(type: .appSwitch, appName: front.localizedName ?? "Unknown", details: front.bundleIdentifier ?? ""))
        }
    }
    public func stop() {
        if let observer = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer); appObserver = nil }
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
    }
}

@MainActor
public final class ScreenActionCaptureService: WorkflowRecording {
    public private(set) var isRecording = false
    private let source: any WorkflowEventSource
    private let maximumActions: Int
    private let maximumSeconds: TimeInterval
    private var buffer: WorkflowCaptureBuffer?
    private var generation = UUID()
    private var deadline: Task<Void, Never>?
    private var limitHandler: (@MainActor (WorkflowSession) -> Void)?
    public init(source: any WorkflowEventSource = NativeWorkflowEventSource(), maximumActions: Int = 10_000, maximumSeconds: TimeInterval = 3600) {
        self.source = source; self.maximumActions = min(10_000, max(1, maximumActions))
        self.maximumSeconds = min(3600, max(0.001, maximumSeconds))
    }
    public func start(sessionTitle: String, onLimit: @escaping @MainActor (WorkflowSession) -> Void) throws {
        guard !isRecording else { throw StoreError(message: "Workflow recording already active") }
        generation = UUID(); let id = generation
        buffer = WorkflowCaptureBuffer(title: sessionTitle, maximumActions: maximumActions, maximumSeconds: maximumSeconds)
        limitHandler = onLimit; isRecording = true
        do { try source.start { [weak self] action in self?.accept(action, generation: id) } }
        catch { _ = stop(); throw error }
        guard generation == id, isRecording else { return }
        deadline = Task { [weak self, maximumSeconds] in
            do { try await Task.sleep(for: .seconds(maximumSeconds)) } catch { return }
            guard let self, self.generation == id else { return }
            self.reachedLimit()
        }
    }
    private func accept(_ action: CapturedAction, generation id: UUID) {
        guard isRecording, id == generation else { return }
        if buffer?.append(action) == false { reachedLimit() }
    }
    private func reachedLimit() {
        let handler = limitHandler
        if let session = stop() { handler?(session) }
    }
    public func stop() -> WorkflowSession? {
        generation = UUID(); isRecording = false; deadline?.cancel(); deadline = nil
        source.stop()
        var session = buffer?.session; session?.endedAt = Date()
        buffer = nil; limitHandler = nil
        return session
    }
}
