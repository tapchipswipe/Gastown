import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

public enum WindowSnapAction: String, Sendable, CaseIterable, Identifiable {
    case leftHalf = "Left Half (50%)"
    case rightHalf = "Right Half (50%)"
    case rightHalfAlt = "Right Half (2/3)"
    case maximize = "Maximize Window"
    case center = "Center Window"
    case leftThird = "Left Third (33%)"
    case rightTwoThirds = "Right Two-Thirds (66%)"
    case topHalf = "Top Half"
    case bottomHalf = "Bottom Half"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .leftHalf: return "rectangle.leadinghalf.filled"
        case .rightHalf: return "rectangle.trailinghalf.filled"
        case .rightHalfAlt: return "rectangle.split.2x1.fill"
        case .maximize: return "rectangle.inset.filled"
        case .center: return "rectangle.center.inset.filled"
        case .leftThird: return "rectangle.split.3x1"
        case .rightTwoThirds: return "rectangle.split.3x1.fill"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        }
    }
}

/// Pure Swift 6 window layout and snapping engine using macOS Accessibility APIs.
public final class WindowSnapEngine: @unchecked Sendable {
    public static let shared = WindowSnapEngine()

    private var previousFrames: [pid_t: CGRect] = [:]
    private let lock = NSLock()

    public init() {}

    /// Computes target frame for a given snap action within a screen's visible area in AX coordinates.
    public static func targetFrame(for action: WindowSnapAction, on screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame

        // Convert NSScreen visibleFrame (bottom-left origin) to AX frame (top-left origin)
        let axTop = primaryHeight - visible.maxY
        let axBounds = CGRect(x: visible.minX, y: axTop, width: visible.width, height: visible.height)

        switch action {
        case .leftHalf:
            return CGRect(x: axBounds.minX, y: axBounds.minY, width: axBounds.width / 2.0, height: axBounds.height)
        case .rightHalf:
            return CGRect(x: axBounds.minX + (axBounds.width / 2.0), y: axBounds.minY, width: axBounds.width / 2.0, height: axBounds.height)
        case .rightHalfAlt:
            return CGRect(x: axBounds.minX + (axBounds.width / 3.0), y: axBounds.minY, width: (axBounds.width * 2.0) / 3.0, height: axBounds.height)
        case .maximize:
            return axBounds
        case .center:
            let w = min(axBounds.width * 0.75, 1200)
            let h = min(axBounds.height * 0.80, 850)
            return CGRect(x: axBounds.midX - (w / 2.0), y: axBounds.midY - (h / 2.0), width: w, height: h)
        case .leftThird:
            return CGRect(x: axBounds.minX, y: axBounds.minY, width: axBounds.width / 3.0, height: axBounds.height)
        case .rightTwoThirds:
            return CGRect(x: axBounds.minX + (axBounds.width / 3.0), y: axBounds.minY, width: (axBounds.width * 2.0) / 3.0, height: axBounds.height)
        case .topHalf:
            return CGRect(x: axBounds.minX, y: axBounds.minY, width: axBounds.width, height: axBounds.height / 2.0)
        case .bottomHalf:
            return CGRect(x: axBounds.minX, y: axBounds.minY + (axBounds.height / 2.0), width: axBounds.width, height: axBounds.height / 2.0)
        }
    }

    /// Snaps the frontmost window according to the specified action.
    @discardableResult
    public func snapFrontmostWindow(to action: WindowSnapAction) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        guard err == .success, let window = focusedWindowValue else {
            return false
        }
        let windowElement = window as! AXUIElement

        // Determine screen
        let targetScreen = NSScreen.main ?? NSScreen.screens.first!
        let targetRect = Self.targetFrame(for: action, on: targetScreen)

        // Save current frame for restore
        if let currentFrame = readWindowFrame(windowElement) {
            lock.lock()
            previousFrames[pid] = currentFrame
            lock.unlock()
        }

        return applyWindowFrame(windowElement, frame: targetRect)
    }

    private func readWindowFrame(_ window: AXUIElement) -> CGRect? {
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posVal = posVal, let sizeVal = sizeVal else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: pos, size: size)
    }

    private func applyWindowFrame(_ window: AXUIElement, frame: CGRect) -> Bool {
        var pos = frame.origin
        var size = frame.size

        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)

        // Try setting position again in case window size constraint affected origin
        if posResult == .success && sizeResult == .success {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
            return true
        }
        return posResult == .success || sizeResult == .success
    }
}
