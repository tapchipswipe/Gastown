import AppKit
import SwiftUI
import NewtonCore

public final class ShelfPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

@MainActor
public final class ShelfWindowController: NSObject {
    public static let shared = ShelfWindowController()

    private var panel: ShelfPanel?

    public var isVisible: Bool { panel != nil }

    public func show() {
        if let p = panel {
            p.orderFrontRegardless()
            return
        }

        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 304
        let height: CGFloat = 400
        // Dock on the right edge of the screen
        let originX = screen.visibleFrame.maxX - width - 16
        let originY = screen.visibleFrame.midY - (height / 2)
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        let p = ShelfPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true

        let view = ShelfView { [weak self] in
            self?.hide()
        }

        p.contentView = NSHostingView(rootView: view)
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
}
