import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

public final class CommandBarPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func cancelOperation(_ sender: Any?) {
        CommandBarWindowController.shared.hide()
    }
}

@MainActor
public final class CommandBarWindowController: NSObject {
    public static let shared = CommandBarWindowController()

    private var panel: CommandBarPanel?
    private weak var workspaceModel: WorkspaceModel?

    public var isVisible: Bool { panel != nil }

    public func configure(with model: WorkspaceModel) {
        self.workspaceModel = model
    }

    public func show() {
        if let p = panel {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 580
        let height: CGFloat = 380
        let originX = screen.frame.midX - (width / 2)
        let originY = screen.frame.midY - (height / 2) + 80
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        let p = CommandBarPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true

        let view = CommandBarView(model: workspaceModel ?? WorkspaceModel()) { [weak self] in
            self?.hide()
        }

        p.contentView = NSHostingView(rootView: view)
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
