import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

/// Manages Newton's primary menu bar presence with Option A readouts:
/// Displays SoC wattage, battery runway, and active git branch directly in the status bar item.
@MainActor
public final class StatusItemController: NSObject, NSPopoverDelegate {
    public static let shared = StatusItemController()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private weak var workspace: WorkspaceModel?

    public override init() {
        super.init()
    }

    public func configure(with model: WorkspaceModel) {
        self.workspace = model
        setupStatusItem()
        setupPopover()
        startRefreshTimer()
        updateReadout()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self

        guard let ws = workspace else { return }
        let hosting = NSHostingController(rootView: MenuPanelView(model: ws))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateReadout()
            }
        }
    }

    /// Updates Option A menu bar readout: "4.2W · 6h 45m · newton:main"
    public func updateReadout() {
        guard let button = statusItem?.button else { return }
        let project = workspace?.trackedProjects.first

        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            let power = await Task.detached(priority: .utility) { PowerPacingEngine.captureSnapshot() }.value
            guard !Task.isCancelled else { return }

            var readoutParts: [String] = []
            if self?.workspace?.speech.isRecording == true || self?.workspace?.systemSpeech.isRecording == true { readoutParts.append("● Recording") }

            // 1. SoC Package Power (Watts)
            if let watts = power.estimatedWatts {
                readoutParts.append(String(format: "Battery %.1fW", watts))
            } else if let percent = power.batteryPercent {
                readoutParts.append("\(percent)%")
            }

            // 2. Battery Runway
            readoutParts.append(power.runwayFormatted)

            // 3. Active Project / Branch
            if let p = project {
                readoutParts.append("Recent \(p.name):\(p.activeBranch)")
            } else {
                readoutParts.append("Newton")
            }

            let fullReadout = readoutParts.joined(separator: " · ")

            await MainActor.run { [weak self] in
                guard self != nil else { return }
                button.image = NSImage(systemSymbolName: "atom", accessibilityDescription: "Newton")
                button.imagePosition = .imageLeading
                button.title = " " + fullReadout
                button.toolTip = "Newton Super-App (Click to open Menu Panel, Right-click for options)"
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(anchor: sender)
        }
    }

    public func togglePopover(anchor: NSStatusBarButton? = nil) {
        guard let button = anchor ?? statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu(title: "Newton")
        menu.addItem(NSMenuItem(title: "Open Workspace", action: #selector(openWorkspace), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Dynamic Notch Island", action: #selector(toggleNotch), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle ⌘K Command Palette", action: #selector(toggleCommandBar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Desktop Glass HUD", action: #selector(toggleHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Floating Drop Shelf", action: #selector(toggleShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: workspace?.isPaused == true ? "Resume Selected Services" : "Pause All", action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Newton", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil // Restore button action behavior
    }

    @objc private func openWorkspace() { workspace?.perform(.navigate("Mission Control")) }
    @objc private func togglePause() { if workspace?.isPaused == true { workspace?.resumeAll() } else { workspace?.pauseAll() } }
    @objc private func toggleNotch() { NotchWindowController.shared.toggle() }
    @objc private func toggleCommandBar() { CommandBarWindowController.shared.toggle() }
    @objc private func toggleHUD() { DesktopHUDWindowController.shared.toggle() }
    @objc private func toggleShelf() { ShelfWindowController.shared.toggle() }
    @objc private func openSettings() { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
