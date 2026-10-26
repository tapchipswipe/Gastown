import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import NewtonCore

struct Phase2SuperAppTests {

    // MARK: - WindowSnapEngine Tests

    @Test func testWindowSnapActionsCoverage() {
        #expect(WindowSnapAction.allCases.count >= 9)
        for action in WindowSnapAction.allCases {
            #expect(!action.iconName.isEmpty)
            #expect(!action.rawValue.isEmpty)
        }
    }

    @Test func testWindowSnapTargetFrameMath() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        let leftHalf = WindowSnapEngine.targetFrame(for: .leftHalf, on: screen)
        #expect(abs(leftHalf.width - (visible.width / 2.0)) < 1.0)
        #expect(abs(leftHalf.height - visible.height) < 1.0)

        let rightHalf = WindowSnapEngine.targetFrame(for: .rightHalf, on: screen)
        #expect(abs(rightHalf.width - (visible.width / 2.0)) < 1.0)
        #expect(rightHalf.minX > leftHalf.minX)

        let maxRect = WindowSnapEngine.targetFrame(for: .maximize, on: screen)
        #expect(abs(maxRect.width - visible.width) < 1.0)
        #expect(abs(maxRect.height - visible.height) < 1.0)

        let centerRect = WindowSnapEngine.targetFrame(for: .center, on: screen)
        #expect(centerRect.width <= visible.width)
        #expect(centerRect.height <= visible.height)
    }

    // MARK: - PortManagerEngine Tests

    @Test func testPortManagerParsesLsofOutput() {
        let mockLsof = """
        COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345 lucasdespot   23u  IPv4 0x1234567890abcdef      0t0  TCP *:3000 (LISTEN)
        python3   23456 lucasdespot    4u  IPv6 0xabcdef1234567890      0t0  TCP [::1]:8080 (LISTEN)
        vite      34567 lucasdespot   12u  IPv4 0x9988776655443322      0t0  TCP 127.0.0.1:5173 (LISTEN)
        """

        let entries = PortManagerEngine.parseLsofOutput(mockLsof)
        #expect(entries.count == 3)

        // Sorted by port
        #expect(entries[0].port == 3000)
        #expect(entries[0].pid == 12345)
        #expect(entries[0].processName == "node")

        #expect(entries[1].port == 5173)
        #expect(entries[1].pid == 34567)
        #expect(entries[1].processName == "vite")

        #expect(entries[2].port == 8080)
        #expect(entries[2].pid == 23456)
        #expect(entries[2].processName == "python3")
    }

    @Test func testTerminatePortRejectsUnverifiedIdentity() async {
        for pid: pid_t in [0, 1, -1] {
            await #expect(throws: StoreError.self) {
                try await PortManagerEngine.terminatePort(PortEntry(pid: pid, port: 80, processName: "unknown", user: "unknown", address: "*"))
            }
        }
    }

    // MARK: - VisionCapture Frame Hash Deduplication Tests

    @Test func testFrameHashDeduplication() async throws {
        // Create 2 identical test images and 1 different image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx1 = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: colorSpace, bitmapInfo: bitmapInfo),
              let ctx2 = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: colorSpace, bitmapInfo: bitmapInfo),
              let ctx3 = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128 * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return
        }

        ctx1.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx1.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let img1 = ctx1.makeImage() else { return }

        ctx2.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx2.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let img2 = ctx2.makeImage() else { return }

        ctx3.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx3.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        guard let img3 = ctx3.makeImage() else { return }

        let engine = VisionCaptureEngine()
        let hash1 = await engine.computeFrameHash(for: img1)
        let hash2 = await engine.computeFrameHash(for: img2)
        let hash3 = await engine.computeFrameHash(for: img3)

        #expect(hash1 == hash2)
        #expect(hash1 != hash3)
    }

    // MARK: - Deep Pipes Automation Tests

    @Test func testSynthesizeMissedToDosExtractsCommitments() {
        let events = [
            HistoryEvent(source: "Slack", title: "Can you send the updated pitch deck?"),
            HistoryEvent(source: "Cursor", title: "TODO: fix memory leak in window snapper"),
            HistoryEvent(source: "Email", title: "I will deploy the staging build by Friday"),
            HistoryEvent(source: "Safari", title: "Browsing Apple Developer docs")
        ]

        let report = PipeAutomationEngine.synthesizeMissedToDos(events: events)
        #expect(report.waitingOnMe.contains(where: { $0.contains("pitch deck") }))
        #expect(report.quickWins.contains(where: { $0.contains("window snapper") }))
        #expect(report.likelyMissed.contains(where: { $0.contains("staging build") }))
        #expect(report.fullMarkdown.contains("# ✅ Missed To-Dos & Commitments Radar"))
    }

    @Test func testSynthesizeMeetingDigestExtractsDecisionsAndActions() {
        let notes = """
        Product sync with engineering team.
        Decided: Keep 0% idle CPU policy across all background daemons.
        Agreed: Window snapping will use native macOS Accessibility APIs.
        Action item: Implement Phase 2 tests and build release v0.1.8.
        Assigned to Lucas: Review financial forecast accuracy.
        """

        let digest = PipeAutomationEngine.synthesizeMeetingDigest(title: "Architecture Review", notes: notes)
        #expect(digest.title == "Architecture Review")
        #expect(digest.decisions.count >= 2)
        #expect(digest.actionItems.count >= 2)
        #expect(digest.fullMarkdown.contains("Architecture Review"))
        #expect(digest.fullMarkdown.contains("Keep 0% idle CPU"))
    }

    // MARK: - AudioFlowProfilerEngine Tests

    @Test func missingAudioMeasurementsAreUnavailable() {
        let report = AudioFlowProfilerEngine.analyzeAudioFlow(tracks: [NowPlayingTrack(title: "Time", artist: "Hans Zimmer")])
        #expect(report.flowStateVelocityBoostPercent == nil)
        #expect(report.topTracks.first?.avgFocusScore == nil)
        #expect(report.topTracks.first?.playMinutes == nil)
    }

    @Test func testAudioFlowReportSynthesis() {
        let tracks = [
            NowPlayingTrack(title: "Time", artist: "Hans Zimmer", album: "Inception", isPlaying: true, source: "Apple Music"),
            NowPlayingTrack(title: "Time", artist: "Hans Zimmer", album: "Inception", isPlaying: true, source: "Apple Music"),
            NowPlayingTrack(title: "Cornfield Chase", artist: "Hans Zimmer", album: "Interstellar", isPlaying: true, source: "Apple Music"),
            NowPlayingTrack(title: "Solaris", artist: "Cliff Martinez", album: "Solaris", isPlaying: true, source: "Spotify")
        ]

        let report = AudioFlowProfilerEngine.analyzeAudioFlow(tracks: tracks, keystrokes: 2400, focusMinutes: 45)
        #expect(report.isLiveSession == true)
        #expect(report.topArtist == "Hans Zimmer")
        #expect(report.topTracks.first?.title == "Time")
        #expect(report.topTracks.first?.playCount == 2)
        #expect(report.flowStateVelocityBoostPercent == nil)
        #expect(!report.summary.contains("WPM boost"))
    }

    // MARK: - iCloudStorageOptimizer Tests

    @Test func testGhostFolderItemRatioCalculations() {
        let fullyGhosted = GhostFolderItem(name: "Archive", path: "/test/archive", totalSizeBytes: 10_000_000, localSizeBytes: 0)
        #expect(fullyGhosted.ghostRatio == 1.0)

        let fullyLocal = GhostFolderItem(name: "ActiveRepo", path: "/test/repo", totalSizeBytes: 5_000_000, localSizeBytes: 5_000_000)
        #expect(fullyLocal.ghostRatio == 0.0)

        let halfGhosted = GhostFolderItem(name: "Media", path: "/test/media", totalSizeBytes: 10_000_000, localSizeBytes: 5_000_000)
        #expect(abs(halfGhosted.ghostRatio - 0.5) < 0.001)

        let empty = GhostFolderItem(name: "Empty", path: "/test/empty", totalSizeBytes: 0, localSizeBytes: 0)
        #expect(empty.ghostRatio == 0.0)
    }
}
