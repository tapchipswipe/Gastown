// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import Foundation

public enum QuitProtectionShortcut: String, Sendable, CaseIterable {
    case quit = "Quit (⌘Q)"
    case close = "Close Window (⌘W)"
}

public enum QuitProtectionMode: String, Sendable, CaseIterable {
    case holdToConfirm = "Hold to Confirm"
    case disabled = "Disabled"
}

public struct QuitProtectionConfig: Sendable, Equatable {
    public var isEnabled: Bool
    public var mode: QuitProtectionMode
    public var holdDurationSeconds: Double
    public var protectedBundleIDs: Set<String>

    public init(
        isEnabled: Bool = true,
        mode: QuitProtectionMode = .holdToConfirm,
        holdDurationSeconds: Double = 0.8,
        protectedBundleIDs: Set<String> = [
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.microsoft.VSCode",          // VS Code
            "com.apple.dt.Xcode",            // Xcode
            "com.apple.Terminal",            // Terminal
            "com.googlecode.iterm2",         // iTerm2
            "com.google.Chrome",             // Google Chrome
            "com.apple.Safari"               // Safari
        ]
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.holdDurationSeconds = holdDurationSeconds
        self.protectedBundleIDs = protectedBundleIDs
    }
}

public final class QuitProtectionEngine: @unchecked Sendable {
    public static let shared = QuitProtectionEngine()

    private let lock = NSLock()
    private var _config: QuitProtectionConfig

    public var config: QuitProtectionConfig {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _config
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _config = newValue
        }
    }

    public init(config: QuitProtectionConfig = QuitProtectionConfig()) {
        self._config = config
    }

    public func shouldIntercept(shortcut: QuitProtectionShortcut, bundleID: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard _config.isEnabled, _config.mode != .disabled else { return false }
        guard let bundleID = bundleID else { return false }
        return _config.protectedBundleIDs.contains(bundleID)
    }

    public final class HoldSession: Sendable {
        public let shortcut: QuitProtectionShortcut
        public let appName: String
        public let bundleID: String
        public let startTime: Date
        public let duration: Double

        public var deadline: Date {
            startTime.addingTimeInterval(duration)
        }

        public init(shortcut: QuitProtectionShortcut, appName: String, bundleID: String, duration: Double, startTime: Date = Date()) {
            self.shortcut = shortcut
            self.appName = appName
            self.bundleID = bundleID
            self.duration = max(0.2, duration)
            self.startTime = startTime
        }

        public func progress(at now: Date = Date()) -> Double {
            let elapsed = now.timeIntervalSince(startTime)
            return min(1.0, max(0.0, elapsed / duration))
        }

        public func isCompleted(at now: Date = Date()) -> Bool {
            return now >= deadline
        }
    }

    public func startHold(shortcut: QuitProtectionShortcut, appName: String, bundleID: String, now: Date = Date()) -> HoldSession {
        let duration = config.holdDurationSeconds
        return HoldSession(shortcut: shortcut, appName: appName, bundleID: bundleID, duration: duration, startTime: now)
    }

    public func addProtectedApp(bundleID: String) {
        lock.lock()
        defer { lock.unlock() }
        _config.protectedBundleIDs.insert(bundleID)
    }

    public func removeProtectedApp(bundleID: String) {
        lock.lock()
        defer { lock.unlock() }
        _config.protectedBundleIDs.remove(bundleID)
    }
}
