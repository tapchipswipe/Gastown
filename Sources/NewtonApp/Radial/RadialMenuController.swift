import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

@MainActor
public final class RadialMenuController: NSObject {
    public static let shared = RadialMenuController()

    private var panel: NSPanel?
    private var highlightedIndex: Int?
    private weak var workspaceModel: WorkspaceModel?

    public var isVisible: Bool { panel != nil }

    public func configure(with model: WorkspaceModel) {
        self.workspaceModel = model
    }

    public func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    public func show() {
        if isVisible {
            dismiss()
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let panelSize: CGFloat = 340
        let x = mouseLocation.x - (panelSize / 2)
        let y = mouseLocation.y - (panelSize / 2)
        let frame = CGRect(x: x, y: y, width: panelSize, height: panelSize)

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

        let items: [RadialSliceItem] = [
            RadialSliceItem(title: "Snap Left", iconName: "rectangle.lefthalf.filled") { [weak self] in
                self?.workspaceModel?.perform(.snap(.leftHalf))
            },
            RadialSliceItem(title: "Snap Right", iconName: "rectangle.righthalf.filled") { [weak self] in
                self?.workspaceModel?.perform(.snap(.rightHalf))
            },
            RadialSliceItem(title: "Maximize", iconName: "rectangle.fill") { [weak self] in
                self?.workspaceModel?.perform(.snap(.maximize))
            },
            RadialSliceItem(title: "Center", iconName: "rectangle.center.inset.filled") { [weak self] in
                self?.workspaceModel?.perform(.snap(.center))
            },
            RadialSliceItem(title: "Awake", iconName: "sun.max.fill") { [weak self] in
                guard let ws = self?.workspaceModel else { return }
                ws.perform(.toggleAwake)
            },
            RadialSliceItem(title: "Mute Mic", iconName: "mic.slash.fill") { [weak self] in
                self?.workspaceModel?.perform(.presentation(.muteMicrophone))
            },
            RadialSliceItem(title: "Sampler", iconName: "eyedropper") { [weak self] in
                self?.workspaceModel?.perform(.presentation(.sampleColor))
            },
            RadialSliceItem(title: "Clean", iconName: "keyboard") { [weak self] in
                self?.workspaceModel?.perform(.toggleCleaning)
            },
            RadialSliceItem(title: "Pin", iconName: "pin.fill") { [weak self] in
                self?.workspaceModel?.perform(.presentation(.pinLatest))
            },
            RadialSliceItem(title: "Sweep", iconName: "bolt.fill") { [weak self] in
                self?.workspaceModel?.perform(.scanCleanup)
            }
        ]

        let radialView = RadialMenuView(
            items: items,
            highlightedIndex: Binding(
                get: { [weak self] in self?.highlightedIndex },
                set: { [weak self] in self?.highlightedIndex = $0 }
            ),
            onSelect: { [weak self] item in
                self?.dismiss()
                item.action()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        p.contentView = NSHostingView(rootView: radialView)
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        self.panel = p
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        highlightedIndex = nil
    }
}
