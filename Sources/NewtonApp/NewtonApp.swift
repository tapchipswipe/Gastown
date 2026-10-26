import SwiftUI
import NewtonCore
import NewtonWorkspace

@main
struct NewtonApp: App {
    @NSApplicationDelegateAdaptor(NewtonAppDelegate.self) private var delegate
    private var model: WorkspaceModel { delegate.workspace }

    var body: some Scene {
        Settings { SettingsView(model: model) }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Lumen History…", action: model.importLumen)
                    .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(!model.ready || model.importBusy || model.deleteBusy || model.isStopping)
            }
            CommandMenu("Overlays") {
                Button("Toggle ⌘K Command Palette") {
                    CommandBarWindowController.shared.configure(with: model)
                    CommandBarWindowController.shared.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Toggle Dynamic Notch Island") {
                    NotchWindowController.shared.configure(with: model)
                    NotchWindowController.shared.toggle()
                }
                .keyboardShortcut("n", modifiers: [.option])

                Button("Toggle Floating Drop Shelf") {
                    ShelfWindowController.shared.toggle()
                }
                .keyboardShortcut("s", modifiers: [.option])

                Button("Toggle Desktop Glass HUD") {
                    DesktopHUDWindowController.shared.configure(with: model)
                    DesktopHUDWindowController.shared.toggle()
                }
                .keyboardShortcut("h", modifiers: [.option])
            }
            CommandMenu("Tools") {
                Button(model.enabled.contains(.keepAwake) ? "Allow Idle Sleep" : "Keep Awake") {
                    model.toggle(.keepAwake, enabled: !model.enabled.contains(.keepAwake))
                }.keyboardShortcut("k", modifiers: [.command, .shift]).disabled(!model.ready)
                Button("Show Local Data", action: model.revealStorage)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class NewtonAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let workspace: WorkspaceModel
    private var terminating = false
    private var workspaceWindow: NSWindow?

    override init() {
        workspace = WorkspaceModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        workspace.presentationCommand = { [weak self] command in self?.performPresentation(command) }
        workspace.openWorkspace = { [weak self] in self?.showWorkspace() }
        StatusItemController.shared.configure(with: workspace)
        GlobalHotkeyEngine.shared.start()
        if let status = GlobalHotkeyEngine.shared.installationStatus, status != 0 {
            workspace.errorMessage = "Global shortcut installation failed (\(status))."
        } else if !GlobalHotkeyEngine.shared.failures.isEmpty {
            workspace.errorMessage = "Shortcut conflicts: " + GlobalHotkeyEngine.shared.failures.sorted { $0.key < $1.key }.map { "Action \($0.key): OSStatus \($0.value)" }.joined(separator: ", ")
        }
        CleaningModeController.shared.configure(with: workspace)
        CommandBarWindowController.shared.configure(with: workspace)
        NotchWindowController.shared.configure(with: workspace)
        DesktopHUDWindowController.shared.configure(with: workspace)
        RadialMenuController.shared.configure(with: workspace)
        Task { [weak self] in
            guard let self else { return }
            await self.workspace.open()
            self.showWorkspace()
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleMenuPanel"), object: nil, queue: .main) { _ in
            Task { @MainActor in StatusItemController.shared.togglePopover() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleCommandBar"), object: nil, queue: .main) { _ in
            Task { @MainActor in CommandBarWindowController.shared.toggle() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleNotch"), object: nil, queue: .main) { _ in
            Task { @MainActor in NotchWindowController.shared.toggle() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleHUD"), object: nil, queue: .main) { _ in
            Task { @MainActor in DesktopHUDWindowController.shared.toggle() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleWindowSwitcher"), object: nil, queue: .main) { _ in
            Task { @MainActor in WindowSwitcherController.shared.show() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewtonToggleRadialMenu"), object: nil, queue: .main) { _ in
            Task { @MainActor in RadialMenuController.shared.toggle() }
        }
    }

    func performPresentation(_ command: WorkspacePresentationCommand) {
        switch command {
        case .commandBar: CommandBarWindowController.shared.toggle()
        case .notch: NotchWindowController.shared.toggle()
        case .hud: DesktopHUDWindowController.shared.toggle()
        case .shelf: ShelfWindowController.shared.toggle()
        case .sampleColor: Task { _ = await ColorSampler.shared.sampleColor() }
        case .muteMicrophone: MicMuteController.shared.toggleMute()
        case .closePins: ScreenshotPinController.shared.closeAll()
        case .pinText(let title,let text): ScreenshotPinController.shared.pinMoment(title: title,text: text)
        case .pinLatest:
            guard let event = workspace.events.first else { workspace.errorMessage = "No saved observation available to pin"; return }
            ScreenshotPinController.shared.pinMoment(title: event.title,text: event.detail)
        }
    }

    func showWorkspace() {
        workspace.setPresentationVisible(true)
        if let workspaceWindow { workspaceWindow.makeKeyAndOrderFront(nil) }
        else {
            let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1140,height: 780),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
            window.title = "Newton"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentViewController = NSHostingController(rootView: WorkspaceView(model: workspace))
            window.center(); workspaceWindow = window; window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,window === workspaceWindow { workspace.setPresentationVisible(false) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            do { try await workspace.shutdown(); GlobalHotkeyEngine.shared.stop(); sender.reply(toApplicationShouldTerminate: true) }
            catch {
                terminating = false
                sender.reply(toApplicationShouldTerminate: false)
                workspace.errorMessage = nil
                let alert = NSAlert()
                alert.messageText = "Newton kept running to protect unsaved work"
                alert.informativeText = error.localizedDescription + " Open Newton from its menu-bar icon to retry."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
        return .terminateLater
    }
}
