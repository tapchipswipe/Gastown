import AppKit
import Carbon.HIToolbox
import Observation
import NewtonCore

@MainActor public protocol KeyboardTapInstalling: AnyObject {
    func install(_ intercept: @escaping @MainActor (CGEventType, CGEvent) -> Bool) -> Bool
    func stop()
}

/// The tap and its callback live exclusively on the main CFRunLoop.
@MainActor public final class NativeKeyboardTap: KeyboardTapInstalling {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var intercept: (@MainActor (CGEventType, CGEvent) -> Bool)?
    public init() {}
    public func install(_ intercept: @escaping @MainActor (CGEventType, CGEvent) -> Bool) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        self.intercept = intercept
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let swallowed = MainActor.assumeIsolated {
                let driver = Unmanaged<NativeKeyboardTap>.fromOpaque(context).takeUnretainedValue()
                return driver.intercept?(type, event) == true
            }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { self.intercept = nil; return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { stop(); return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); return false }
        return true
    }
    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; intercept = nil
    }
}

@MainActor @Observable public final class KeyboardProtectionService {
    public private(set) var state = ServiceLifecycle(.disabled, reason: "Keyboard interception off")
    public private(set) var quitEnabled = false
    public private(set) var cleaningActive = false
    public private(set) var unlockProgress = 0
    public var onUnlockProgress: (@MainActor (Int) -> Void)?
    public var onCleaningChanged: (@MainActor (Bool) -> Void)?
    public var onHoldChanged: (@MainActor (String?, QuitProtectionShortcut, Double) -> Void)?
    @ObservationIgnored private let driver: any KeyboardTapInstalling
    @ObservationIgnored private var policy = KeyboardPolicy()
    @ObservationIgnored private var healthTask: Task<Void,Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
    @ObservationIgnored private let foreground: @MainActor () -> NSRunningApplication?
    public static let syntheticMarker: Int64 = 0x4E57544E
    public init(driver: any KeyboardTapInstalling = NativeKeyboardTap(),
                foreground: @escaping @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }) {
        self.driver = driver; self.foreground = foreground
    }
    public func setQuitProtection(_ value: Bool) {
        quitEnabled = value
        if value { _ = ensureInstalled() }
        else if !cleaningActive { stopTap() }
    }
    @discardableResult public func startCleaning() -> Bool {
        guard !suspended, ensureInstalled() else { return false }
        cancelHold(); policy.reset(); policy.cleaning = true
        cleaningActive = true; unlockProgress = 0; onCleaningChanged?(true)
        return true
    }
    public func stopCleaning() {
        cleaningActive = false; unlockProgress = 0; policy.reset(); onCleaningChanged?(false)
        if !quitEnabled { stopTap() }
    }
    public func setSuspended(_ value: Bool) {
        suspended = value
        if value { stopCleaning(); stopTap(); state = ServiceLifecycle(.paused, reason: "Pause All, lock or sleep") }
        else if quitEnabled { _ = ensureInstalled() }
    }
    public func stop() { quitEnabled = false; stopCleaning(); stopTap() }
    private func ensureInstalled() -> Bool {
        guard !suspended else { return false }
        if installed { return true }
        state = ServiceLifecycle(.starting, reason: "Installing global keyboard tap")
        installed = driver.install { [weak self] type, event in self?.intercept(type, event) ?? false }
        guard installed else {
            state = ServiceLifecycle(.blocked, reason: "Accessibility permission or global keyboard tap unavailable. Protection is inactive.")
            return false
        }
        state = ServiceLifecycle(.running, reason: "Global keyboard interception installed")
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self,self.installed else { return }
                if !AXIsProcessTrusted() {
                    self.stopCleaning(); self.stopTap()
                    self.state = ServiceLifecycle(.blocked,reason: "Accessibility permission lost; keyboard interception inactive"); return
                }
            }
        }
        foregroundObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelHold() }
        }
        return true
    }
    private func cancelHold() {
        holdTask?.cancel(); holdTask = nil; policy.cancel(); onHoldChanged?(nil, .quit, 0)
    }
    private func stopTap() {
        healthTask?.cancel(); healthTask = nil
        cancelHold(); driver.stop(); installed = false; policy.reset()
        if let foregroundObserver { NSWorkspace.shared.notificationCenter.removeObserver(foregroundObserver) }
        foregroundObserver = nil
        state = ServiceLifecycle(.disabled, reason: "Keyboard interception off")
    }
    private func intercept(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cleaningActive = false; onCleaningChanged?(false); stopTap()
            state = ServiceLifecycle(.failed, reason: "System disabled keyboard interception. Protection is inactive; enable again to retry.")
            return false
        }
        let app = foreground(), bundle = app?.bundleIdentifier
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return false }
        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) { cancelHold() }
            return cleaningActive
        }
        let result = policy.handle(key: event.getIntegerValueField(.keyboardEventKeycode), down: type == .keyDown,
            command: event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand,
            repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, synthetic: false, bundle: bundle,
            protected: quitEnabled && QuitProtectionEngine.shared.shouldIntercept(shortcut: .quit, bundleID: bundle),
            now: ProcessInfo.processInfo.systemUptime, duration: QuitProtectionEngine.shared.config.holdDurationSeconds)
        unlockProgress = policy.escapePresses; onUnlockProgress?(unlockProgress)
        switch result {
        case .pass: return false
        case .unlock:
            // Defer tap teardown until after the current event returns to CoreGraphics.
            Task { [weak self] in self?.stopCleaning() }; return true
        case .holdCancelled: cancelHold(); return true
        case .swallow: return true
        case .holdStarted:
            let name = app?.localizedName ?? "Application"
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let shortcut: QuitProtectionShortcut = key == 12 ? .quit : .close
            let start = ProcessInfo.processInfo.systemUptime
            let duration = max(0.2, QuitProtectionEngine.shared.config.holdDurationSeconds)
            onHoldChanged?(name, shortcut, 0)
            holdTask?.cancel()
            holdTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                    guard let self, self.installed else { return }
                    guard AXIsProcessTrusted(), self.foreground()?.bundleIdentifier == bundle else { self.cancelHold(); return }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.onHoldChanged?(name, shortcut, min(1, (now - start) / duration))
                    if let key = self.policy.complete(now: now, bundle: bundle) {
                        self.forward(key); self.onHoldChanged?(nil, shortcut, 1); self.holdTask = nil; return
                    }
                }
            }
            return true
        }
    }
    private func forward(_ key: Int64) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = .maskCommand; event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
        state.lastSuccessfulActivity = Date()
    }
}
