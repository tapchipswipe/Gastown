import Testing
import Foundation
@testable import NewtonCore

struct TimeMachineTests {
    func calendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    @Test func elapsedDaysAndRepeatedHours() {
        let c = calendar()
        for (day, count) in [("2026-03-08", 276), ("2026-11-01", 300), ("2026-10-24", 288)] {
            let f = DateFormatter(); f.calendar = c; f.timeZone = c.timeZone; f.dateFormat = "yyyy-MM-dd"
            let frames = TimeMachineEngine.buildTimeline(events: [], calendar: c, targetDate: f.date(from: day)!)
            #expect(frames.count == count)
            #expect(frames.allSatisfy { !$0.hasObservations })
            if count == 300 {
                #expect(frames.filter { $0.timeString.hasPrefix("01:00") }.map(\.timeString) == ["01:00 -04:00", "01:00 -05:00"])
            }
        }
    }
    @Test func allObservationsPreservedAndSortedWithoutInferredMetrics() {
        let date = Date(), c = calendar()
        let events = ["z", "a", "b"].map { HistoryEvent(id: $0, timestamp: date, source: "Lumen · camera", title: "meeting call key") }
        let frames = TimeMachineEngine.buildTimeline(events: events, calendar: c, targetDate: date)
        #expect(frames.flatMap(\.observations).map(\.id) == ["a", "b", "z"])
        #expect(TimeMachineEngine.summarize(timeline: frames).observationCount == 3)
        #expect(TimeMachineEngine.summarize(timeline: frames).observedIntervals == 1)
        for (source, kind) in [("Activity", ObservationKind.activity), ("Screenpipe · ocr", .ocr), ("Time Atlas", .timeAtlas), ("Lumen · focus", .lumen), ("future", .observation)] {
            #expect(ObservationKind(source: source) == kind)
        }
    }
    @Test func markersKeepMultipleProjectsAndDeduplicate() {
        let date = Date()
        let a = TrackedProject(name: "A", path: "/a", activeBranch: "main", condition: .clean, lastCommitMessage: "one", lastCommitDate: date)
        let b = TrackedProject(name: "B", path: "/b", activeBranch: "main", condition: .clean, lastCommitMessage: "two", lastCommitDate: date)
        let frames = TimeMachineEngine.buildTimeline(events: [], trackedProjects: [a,b,a], targetDate: date)
        #expect(frames.flatMap(\.commitMarkers).count == 2)
        #expect(frames.flatMap(\.commitMarkers).allSatisfy { $0.hasPrefix("Latest known commit") })
    }
    @Test func dailySQLBoundariesLimitAndStableOrder() async throws {
        let store = try EventStore(path: ":memory:"), start = Date(timeIntervalSince1970: 10000), end = Date(timeIntervalSince1970: 20000)
        var events = (0..<205).map { HistoryEvent(id: String(format: "%04d", $0), timestamp: start, source: "Activity", title: "record") }
        events += [HistoryEvent(id: "end", timestamp: end, source: "test", title: "exclude"), HistoryEvent(id: "before", timestamp: start.addingTimeInterval(-1), source: "test", title: "exclude")]
        try await store.append(events.reversed())
        let result = try await store.dayEvents(from: start, to: end)
        #expect(result.isComplete && result.events.count == 205)
        #expect(result.events.map(\.id) == events.prefix(205).map(\.id))
        let limited = try await store.dayEvents(from: start, to: end, limit: 100)
        #expect(!limited.isComplete && limited.events.count == 100)
    }
    @Test func defaultDailyLimitExplicitlyTruncatesAtFiftyThousand() async throws {
        let store = try EventStore(path: ":memory:"), start = Date(timeIntervalSince1970: 10000)
        let events = (0..<50_001).map { HistoryEvent(id: String(format: "%05d", $0), timestamp: start, source: "test", title: "observation") }
        try await store.append(events)
        let result = try await store.dayEvents(from: start, to: start.addingTimeInterval(1))
        #expect(result.events.count == 50_000 && !result.isComplete)
        #expect(result.events.last?.id == "49999")
    }
}
