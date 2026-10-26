// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import Foundation

public final class CleaningModeEngine: @unchecked Sendable {
    public static let shared = CleaningModeEngine()

    public enum KeyAction: Sendable, Equatable {
        case swallowed
        case progress(current: Int, threshold: Int)
        case unlocked
    }

    private let lock = NSLock()
    private var _isActive: Bool = false
    private var _consecutiveEscapeCount: Int = 0
    private var _keepScreenVisible: Bool = false
    public let unlockThreshold: Int = 5
    public static let escapeKeyCode: Int64 = 53

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }

    public var consecutiveEscapeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _consecutiveEscapeCount
    }

    public var keepScreenVisible: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _keepScreenVisible
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _keepScreenVisible = newValue
        }
    }

    public init() {}

    public func activate() {
        lock.lock()
        defer { lock.unlock() }
        _isActive = true
        _consecutiveEscapeCount = 0
    }

    public func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        _isActive = false
        _consecutiveEscapeCount = 0
    }

    public func handleKeyEvent(keyCode: Int64) -> KeyAction {
        lock.lock()
        defer { lock.unlock() }

        guard _isActive else { return .swallowed }

        if keyCode == Self.escapeKeyCode {
            _consecutiveEscapeCount += 1
            if _consecutiveEscapeCount >= unlockThreshold {
                _isActive = false
                _consecutiveEscapeCount = 0
                return .unlocked
            } else {
                return .progress(current: _consecutiveEscapeCount, threshold: unlockThreshold)
            }
        } else {
            // Any other key resets the escape counter to prevent accidental wiping from unlocking
            _consecutiveEscapeCount = 0
            return .swallowed
        }
    }
}
