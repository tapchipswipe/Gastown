import Foundation
import Carbon.HIToolbox
import AppKit

public enum GlobalHotKeyAction: UInt32, Sendable {
    case snapLeft = 101
    case snapRight = 102
    case snapMaximize = 103
    case snapCenter = 104
    case toggleCommandBar = 105
    case toggleQuickPanel = 106
    case toggleNotch = 107
    case toggleHUD = 108
    case toggleWindowSwitcher = 109
    case toggleRadialMenu = 110
}

/// Main-run-loop ownership serializes Carbon registration and teardown without locks.
@MainActor public protocol HotkeyRegistering: AnyObject {
    func install(dispatch: @escaping @MainActor (UInt32) -> Void) -> OSStatus
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> OSStatus
    func unregister(id: UInt32)
    func stop()
}

@MainActor public final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private var eventHandler: EventHandlerRef?
    private var keys: [UInt32: EventHotKeyRef] = [:]
    private var dispatch: (@MainActor (UInt32) -> Void)?
    private static let signature: OSType = 0x4E57_544E
    public init() {}
    public func install(dispatch: @escaping @MainActor (UInt32) -> Void) -> OSStatus {
        self.dispatch = dispatch
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetEventDispatcherTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4E57_544E else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatcher callbacks are delivered on the application event loop.
            MainActor.assumeIsolated {
                Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(data).takeUnretainedValue().dispatch?(id.id)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id), GetEventDispatcherTarget(), 0, &ref)
        if result == noErr, let ref { keys[id] = ref }
        return result
    }
    public func unregister(id: UInt32) {
        if let ref = keys.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
    public func stop() {
        for id in Array(keys.keys) { unregister(id: id) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil; dispatch = nil
    }
}

@MainActor public final class GlobalHotkeyEngine {
    public static let shared = GlobalHotkeyEngine()
    private let registrar: any HotkeyRegistering
    private var actionHandlers: [UInt32: @Sendable () -> Void] = [:]
    public private(set) var failures: [UInt32: OSStatus] = [:]
    public private(set) var installationStatus: OSStatus?
    private var started = false
    public init(registrar: any HotkeyRegistering = CarbonHotkeyRegistrar()) { self.registrar = registrar }
    public func start() {
        guard !started else { return }
        let status = registrar.install { [weak self] id in self?.actionHandlers[id]?() }
        installationStatus = status
        guard status == noErr else { registrar.stop(); return }
        started = true
        registerDefaultShortcuts()
    }
    public func registerHotKey(action: GlobalHotKeyAction, keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable () -> Void) {
        guard started else { return }
        let status = registrar.register(id: action.rawValue, keyCode: keyCode, modifiers: modifiers)
        if status == noErr {
            failures.removeValue(forKey: action.rawValue); actionHandlers[action.rawValue] = handler
        } else {
            failures[action.rawValue] = status; actionHandlers.removeValue(forKey: action.rawValue)
        }
    }
    private func registerDefaultShortcuts() {
        let controlOption = UInt32(controlKey | optionKey)

        // Snap Left: ⌃⌥← (Left Arrow = kVK_LeftArrow = 0x7B = 123)
        registerHotKey(action: .snapLeft, keyCode: 123, modifiers: controlOption) {
            WindowSnapEngine.shared.snapFrontmostWindow(to: .leftHalf)
        }

        // Snap Right: ⌃⌥→ (Right Arrow = kVK_RightArrow = 0x7C = 124)
        registerHotKey(action: .snapRight, keyCode: 124, modifiers: controlOption) {
            WindowSnapEngine.shared.snapFrontmostWindow(to: .rightHalf)
        }

        // Snap Maximize: ⌃⌥↩ (Return = kVK_Return = 0x24 = 36)
        registerHotKey(action: .snapMaximize, keyCode: 36, modifiers: controlOption) {
            WindowSnapEngine.shared.snapFrontmostWindow(to: .maximize)
        }

        // Snap Center: ⌃⌥C (C = kVK_ANSI_C = 0x08 = 8)
        registerHotKey(action: .snapCenter, keyCode: 8, modifiers: controlOption) {
            WindowSnapEngine.shared.snapFrontmostWindow(to: .center)
        }

        // Command Bar: ⌥Space (Space = kVK_Space = 0x31 = 49)
        registerHotKey(action: .toggleCommandBar, keyCode: 49, modifiers: UInt32(optionKey)) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleCommandBar"), object: nil)
        }

        // Quick Panel: ⌃⌘V (V = kVK_ANSI_V = 0x09 = 9)
        let controlCmd = UInt32(controlKey | cmdKey)
        registerHotKey(action: .toggleQuickPanel, keyCode: 9, modifiers: controlCmd) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleMenuPanel"), object: nil)
        }

        // Notch: ⌃⌥N (N = kVK_ANSI_N = 0x2D = 45)
        registerHotKey(action: .toggleNotch, keyCode: 45, modifiers: controlOption) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleNotch"), object: nil)
        }

        // HUD: ⌃⌥H (H = kVK_ANSI_H = 0x04 = 4)
        registerHotKey(action: .toggleHUD, keyCode: 4, modifiers: controlOption) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleHUD"), object: nil)
        }

        // Window Switcher: ⌥Tab (Tab = kVK_Tab = 0x30 = 48)
        registerHotKey(action: .toggleWindowSwitcher, keyCode: 48, modifiers: UInt32(optionKey)) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleWindowSwitcher"), object: nil)
        }

        // Radial Menu: ⌃⌥R (R = kVK_ANSI_R = 0x0F = 15)
        registerHotKey(action: .toggleRadialMenu, keyCode: 15, modifiers: controlOption) {
            NotificationCenter.default.post(name: NSNotification.Name("NewtonToggleRadialMenu"), object: nil)
        }
    }

    public func triggerActionForTesting(_ action: GlobalHotKeyAction) { actionHandlers[action.rawValue]?() }
    public func stop() {
        started = false; actionHandlers.removeAll(); failures.removeAll(); registrar.stop()
    }
}
