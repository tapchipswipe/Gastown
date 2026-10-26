// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import Testing
import Foundation
import CoreGraphics
@testable import NewtonCore

@Suite struct VorssaintPhase3Tests {

    // MARK: - 1. Quit Protection Engine Tests
    @Test func testQuitProtectionInterceptionAndAppManagement() {
        let engine = QuitProtectionEngine()

        // Cursor is protected by default
        #expect(engine.shouldIntercept(shortcut: .quit, bundleID: "com.todesktop.230313mzl4w4u92"))
        #expect(engine.shouldIntercept(shortcut: .close, bundleID: "com.apple.dt.Xcode"))

        // Unprotected app
        #expect(!engine.shouldIntercept(shortcut: .quit, bundleID: "com.example.randomapp"))
        #expect(!engine.shouldIntercept(shortcut: .quit, bundleID: nil))

        // Dynamically add and remove
        engine.addProtectedApp(bundleID: "com.example.randomapp")
        #expect(engine.shouldIntercept(shortcut: .quit, bundleID: "com.example.randomapp"))

        engine.removeProtectedApp(bundleID: "com.example.randomapp")
        #expect(!engine.shouldIntercept(shortcut: .quit, bundleID: "com.example.randomapp"))
    }

    @Test func testQuitProtectionHoldSessionProgressAndCompletion() {
        let start = Date()
        let session = QuitProtectionEngine.HoldSession(
            shortcut: .quit,
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            duration: 1.0,
            startTime: start
        )

        #expect(!session.isCompleted(at: start))
        #expect(session.progress(at: start) == 0.0)

        let half = start.addingTimeInterval(0.5)
        #expect(!session.isCompleted(at: half))
        #expect(session.progress(at: half) == 0.5)

        let end = start.addingTimeInterval(1.0)
        #expect(session.isCompleted(at: end))
        #expect(session.progress(at: end) == 1.0)

        let past = start.addingTimeInterval(2.0)
        #expect(session.isCompleted(at: past))
        #expect(session.progress(at: past) == 1.0)
    }

    // MARK: - 2. Keyboard Cleaning Mode Tests
    @Test func testCleaningModeActivationAndUnlockGesture() {
        let engine = CleaningModeEngine()
        #expect(!engine.isActive)

        engine.activate()
        #expect(engine.isActive)
        #expect(engine.consecutiveEscapeCount == 0)

        // Press Escape 1 time (keyCode 53)
        let action1 = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        #expect(action1 == .progress(current: 1, threshold: 5))
        #expect(engine.isActive)

        // Press Escape 2, 3, 4
        _ = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        _ = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        let action4 = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        #expect(action4 == .progress(current: 4, threshold: 5))
        #expect(engine.isActive)

        // Press Escape 5th time -> Should unlock
        let action5 = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        #expect(action5 == .unlocked)
        #expect(!engine.isActive)
        #expect(engine.consecutiveEscapeCount == 0)
    }

    @Test func testCleaningModeNonEscapeKeyResetsCounter() {
        let engine = CleaningModeEngine()
        engine.activate()

        // Press Escape twice
        _ = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        _ = engine.handleKeyEvent(keyCode: CleaningModeEngine.escapeKeyCode)
        #expect(engine.consecutiveEscapeCount == 2)

        // Press 'A' key (keyCode 0)
        let randomKeyAction = engine.handleKeyEvent(keyCode: 0)
        #expect(randomKeyAction == .swallowed)
        #expect(engine.consecutiveEscapeCount == 0) // reset!
        #expect(engine.isActive) // still active!

        engine.deactivate()
        #expect(!engine.isActive)
    }

    // MARK: - 3. Screenshot Pinning Engine Tests
    @Test func testScreenshotPinAspectRatioAndOpacity() {
        let engine = ScreenshotPinEngine()

        // Aspect ratio calculations
        let fit16x9 = ScreenshotPinEngine.calculateAspectRatioFit(width: 1920, height: 1080, maxDimension: 480)
        #expect(fit16x9.width == 480)
        #expect(fit16x9.height == 270)

        let fitSquare = ScreenshotPinEngine.calculateAspectRatioFit(width: 800, height: 800, maxDimension: 400)
        #expect(fitSquare.width == 400)
        #expect(fitSquare.height == 400)

        // Pin lifecycle
        let pin = engine.addPin(title: "Architecture Diagram", width: 400, height: 300)
        #expect(engine.pins.count >= 1)
        #expect(pin.opacity == 1.0)

        engine.setOpacity(id: pin.id, opacity: 0.5)
        let updated = engine.pins.first(where: { $0.id == pin.id })
        #expect(updated?.opacity == 0.5)

        engine.removePin(id: pin.id)
        #expect(engine.pins.first(where: { $0.id == pin.id }) == nil)
    }

    // MARK: - 5. Command Bar Action Registry Tests
    @Test func testCommandBarActionRegistryIncludesPhase3Tools() {
        let actions = CommandBarEngine.standardActions

        #expect(actions.contains(where: { $0.id == "cleanMode" }))
        #expect(actions.contains(where: { $0.id == "pinMoment" }))
        #expect(actions.contains(where: { $0.id == "closePins" }))
        #expect(actions.contains(where: { $0.id == "quitProtect" }))

        let cleanMatches = CommandBarEngine.matchActions(query: "clean")
        #expect(cleanMatches.contains(where: { $0.id == "cleanMode" }))

        let pinMatches = CommandBarEngine.matchActions(query: "pin")
        #expect(pinMatches.contains(where: { $0.id == "pinMoment" }))
    }
}
