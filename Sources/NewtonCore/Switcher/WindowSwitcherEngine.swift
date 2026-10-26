import Foundation
import AppKit
import CoreGraphics

public struct SwitchableWindow: Identifiable, Sendable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let windowTitle: String
    public let bounds: CGRect

    public init(id: CGWindowID, pid: pid_t, appName: String, windowTitle: String, bounds: CGRect) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.windowTitle = windowTitle
        self.bounds = bounds
    }

    public var displayTitle: String {
        if !windowTitle.isEmpty {
            return windowTitle
        }
        return appName
    }
}

public enum WindowSwitcherEngine {
    /// Captures the list of on-screen user-visible application windows in front-to-back z-order.
    public static func captureWindows() -> [SwitchableWindow] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [SwitchableWindow] = []
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for dict in windowInfoList {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != currentPID else { continue }
            guard let appName = dict[kCGWindowOwnerName as String] as? String, !appName.isEmpty else { continue }
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID else { continue }

            // Filter out system utility windows or invisible frames
            let title = dict[kCGWindowName as String] as? String ?? ""
            var bounds = CGRect.zero
            if let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                bounds = rect
            }

            // Exclude minuscule windows (e.g. background helper windows)
            if bounds.width < 50 || bounds.height < 50 {
                continue
            }

            // Avoid duplicate helper processes with no title and standard system names
            if appName == "Dock" || appName == "Window Server" || appName == "Control Center" || appName == "SystemUIServer" {
                continue
            }

            results.append(SwitchableWindow(
                id: windowID,
                pid: pid,
                appName: appName,
                windowTitle: title,
                bounds: bounds
            ))
        }

        return results
    }

    /// Public Accessibility has no reliable universal CGWindowID bridge. Match a unique
    /// title + geometry only after revalidating the selected CG window; ambiguous matches fail.
    @MainActor @discardableResult public static func activate(window: SwitchableWindow) -> String? {
        guard AXIsProcessTrusted() else { return "Accessibility permission is required to raise the selected window." }
        guard captureWindows().contains(where: { $0.id == window.id && $0.pid == window.pid && $0.bounds == window.bounds && $0.windowTitle == window.windowTitle }) else {
            return "The selected window changed or is no longer visible. Refresh the switcher."
        }
        let appElement = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return "The app does not expose Accessibility windows." }
        let matches = windows.filter { element in
            var title: CFTypeRef?, position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success,
                  (title as? String ?? "") == window.windowTitle,
                  AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
            var point = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
                  AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return false }
            return abs(point.x - window.bounds.minX) < 1 && abs(point.y - window.bounds.minY) < 1 && abs(dimensions.width - window.bounds.width) < 1 && abs(dimensions.height - window.bounds.height) < 1
        }
        guard matches.count == 1, let target = matches.first else { return "Selected window identity is ambiguous or unavailable; no other window was activated." }
        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else { return "The app refused to raise the selected window." }
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard NSRunningApplication(processIdentifier: window.pid)?.activate() == true else { return "Window was raised but application activation failed." }
        return nil
    }
}
