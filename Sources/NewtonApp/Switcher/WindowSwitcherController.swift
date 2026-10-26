import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

@MainActor
public final class WindowSwitcherController: NSObject {
    public static let shared = WindowSwitcherController()

    private var panel: NSPanel?
    private var windows: [SwitchableWindow] = []
    private var selectedIndex: Int = 0
    private var keyEventMonitor: Any?

    public var isVisible: Bool { panel != nil }

    public func show() {
        if isVisible {
            stepSelection(forward: true)
            return
        }

        // Query open windows
        let captured = WindowSwitcherEngine.captureWindows()
        guard !captured.isEmpty else { return }
        self.windows = captured
        // Default select the second window (the previous app) if available, otherwise first
        self.selectedIndex = captured.count > 1 ? 1 : 0

        guard let screen = NSScreen.main else { return }

        let cardWidth: CGFloat = 120
        let totalWidth = min(max(CGFloat(captured.count) * cardWidth + 40, 420), 800)
        let totalHeight: CGFloat = 190

        let x = screen.frame.midX - (totalWidth / 2)
        let y = screen.frame.midY - (totalHeight / 2)
        let frame = CGRect(x: x, y: y, width: totalWidth, height: totalHeight)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let switcherView = WindowSwitcherView(
            windows: windows,
            selectedIndex: Binding(
                get: { [weak self] in self?.selectedIndex ?? 0 },
                set: { [weak self] newVal in self?.selectedIndex = newVal }
            ),
            onSelect: { [weak self] chosen in
                self?.commitSelection(chosen)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        p.contentView = NSHostingView(rootView: switcherView)
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        self.panel = p

        installKeyEventMonitor()
    }

    public func stepSelection(forward: Bool) {
        guard !windows.isEmpty else { return }
        if forward {
            selectedIndex = (selectedIndex + 1) % windows.count
        } else {
            selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        }
    }

    public func commitSelection(_ window: SwitchableWindow) {
        dismiss()
        if let reason = WindowSwitcherEngine.activate(window: window) {
            let alert = NSAlert(); alert.messageText = "Selected window unavailable"; alert.informativeText = reason; alert.runModal()
        }
    }

    public func commitCurrent() {
        guard !windows.isEmpty, selectedIndex >= 0, selectedIndex < windows.count else {
            dismiss()
            return
        }
        commitSelection(windows[selectedIndex])
    }

    public func dismiss() {
        removeKeyEventMonitor()
        panel?.orderOut(nil)
        panel = nil
        windows = []
    }

    private func installKeyEventMonitor() {
        removeKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            switch event.keyCode {
            case 53: // Esc
                self.dismiss()
                return nil
            case 36, 49: // Return, Space
                self.commitCurrent()
                return nil
            case 48: // Tab
                let shift = event.modifierFlags.contains(.shift)
                self.stepSelection(forward: !shift)
                return nil
            case 123: // Left Arrow
                self.stepSelection(forward: false)
                return nil
            case 124: // Right Arrow
                self.stepSelection(forward: true)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
}
