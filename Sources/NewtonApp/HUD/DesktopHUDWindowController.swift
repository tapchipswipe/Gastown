import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

@MainActor
public final class DesktopHUDWindowController: NSObject {
    public static let shared = DesktopHUDWindowController()
    private var panel: NSPanel?
    private weak var workspaceModel: WorkspaceModel?

    public var isVisible: Bool { panel != nil }

    public func configure(with model: WorkspaceModel) {
        self.workspaceModel = model
    }

    public func show() {
        if let p = panel {
            p.orderFrontRegardless()
            return
        }

        let width: CGFloat = 380
        let height: CGFloat = 46

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = true

        let view = DesktopHUDView(model: workspaceModel ?? WorkspaceModel())
        p.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - width - 20
            let y = screen.visibleFrame.maxY - height - 20
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

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
