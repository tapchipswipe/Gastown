import AppKit
import Testing
import NewtonCore
@testable import NewtonWorkspace

@MainActor struct NativeServiceTests {
    @Test func workspaceNotificationAdapterDeliversActualNotificationWithoutGlobalCapture() async throws {
        let center = NotificationCenter()
        let service = ActivityService(center: center, frontmost: { nil }, secureInput: { false })
        let (stream, continuation) = AsyncStream<HistoryEvent>.makeStream()
        service.start { continuation.yield($0) }
        let app = NSRunningApplication.current
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: app])
        var iterator = stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.detail == (app.bundleIdentifier ?? ""))
        #expect(event.source == "Activity")
        service.stop(); continuation.finish()
    }
    @Test func secureInputSuppressesActivationObservations() async {
        let center = NotificationCenter()
        let service = ActivityService(center: center, frontmost: { .current }, secureInput: { true })
        var observations = 0
        service.start { _ in observations += 1 }
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        for _ in 0..<10 { await Task.yield() }
        #expect(observations == 0)
        service.stop()
    }

}
