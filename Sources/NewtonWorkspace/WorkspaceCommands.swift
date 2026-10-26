import AppKit
import NewtonCore

public enum WorkspaceCommand: Sendable {
    case pauseAll, resumeAll, toggleAwake, toggleCleaning, toggleQuitProtection, toggleFocusShield
    case scanCleanup
    case navigate(String)
    case report(String)
    case snap(WindowSnapAction)
    case presentation(WorkspacePresentationCommand)
}

public enum WorkspacePresentationCommand: Sendable {
    case commandBar, notch, hud, shelf, sampleColor, muteMicrophone, pinLatest, closePins
    case pinText(String,String)
}
