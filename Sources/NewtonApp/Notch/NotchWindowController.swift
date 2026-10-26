import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

/// Dedicated borderless floating NSPanel for the Vorssaint Dynamic Notch & Island overlay.
public final class NotchPanel: NSPanel {
    public static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]

    public var acceptsKeyFocus = false

    public override var canBecomeKey: Bool { acceptsKeyFocus }
    public override var canBecomeMain: Bool { false }

    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    public override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

@MainActor
public final class NotchWindowController: NSObject {
    public static let shared = NotchWindowController()

    private var panel: NotchPanel?
    private var isExpanded = false
    private weak var workspaceModel: WorkspaceModel?

    public var isVisible: Bool { panel != nil }

    public func configure(with model: WorkspaceModel) {
        self.workspaceModel = model
    }

    public func show() {
        if let existing = panel {
            existing.orderFrontRegardless()
            return
        }

        guard let screen = NSScreen.main else { return }

        let initialSize = CGSize(width: 380, height: 38)
        let frame = calculateFrame(for: initialSize, on: screen)

        let p = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = NotchPanel.overlayCollectionBehavior

        let rootView = NotchExpandedSurfaceView(
            model: workspaceModel ?? WorkspaceModel(),
            isExpanded: Binding(
                get: { [weak self] in self?.isExpanded ?? false },
                set: { [weak self] newVal in
                    self?.setExpanded(newVal)
                }
            )
        )

        p.contentView = NSHostingView(rootView: rootView)
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        self.panel = p
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    public func toggle() {
        if isVisible { hide() } else { show() }
    }

    public func setExpanded(_ expanded: Bool) {
        self.isExpanded = expanded
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }

        let targetSize = expanded ? CGSize(width: 680, height: 260) : CGSize(width: 380, height: 38)
        let targetFrame = calculateFrame(for: targetSize, on: screen)

        p.acceptsKeyFocus = expanded
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
            p.animator().setFrame(targetFrame, display: true)
        }
    }

    private func calculateFrame(for size: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let midX = screenFrame.midX
        let topY = screenFrame.maxY

        let hasHardwareNotch = screen.safeAreaInsets.top > 0
        let originY = hasHardwareNotch ? (topY - size.height) : (topY - size.height - 8)
        let originX = midX - (size.width / 2)

        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}
