import Foundation

/// Normalization is read-only: stored source strings and IDs are preserved.
public enum ObservationKind: String, Sendable {
    case activity, ocr, action, lumen, timeAtlas, project, workflow, observation
    public init(source: String) {
        let label = source.lowercased()
        switch label {
        case "activity", "app_switch": self = .activity
        case "screen_ocr", "screenpipe · ocr": self = .ocr
        case "screen_action": self = .action
        case "lumen_import": self = .lumen
        case "time atlas", "time_atlas": self = .timeAtlas
        case "project_atlas": self = .project
        case "workflow synthesizer": self = .workflow
        default: self = label.hasPrefix("lumen · ") ? .lumen : .observation
        }
    }
}

public struct TimeMachineFrame: Identifiable, Sendable, Equatable {
    public var id: Int { minuteOfDay }
    /// Elapsed minute from local day start, including repeated daylight-saving hours.
    public let minuteOfDay: Int
    public let timeString: String
    public let observations: [HistoryEvent]
    public let commitMarkers: [String]
    public var hasObservations: Bool { !observations.isEmpty || !commitMarkers.isEmpty }
}

public struct DailyTimelineSummary: Sendable, Equatable {
    public let observedIntervals: Int
    public let observationCount: Int
    public let latestKnownMarkers: Int
}

public enum TimeMachineEngine {
    public static func buildTimeline(events: [HistoryEvent], trackedProjects: [TrackedProject] = [],
                                     calendar: Calendar = .current, targetDate: Date = Date()) -> [TimeMachineFrame] {
        guard let day = calendar.dateInterval(of: .day, for: targetDate) else { return [] }
        let count = Int(ceil(day.duration / 300))
        var observations = Array(repeating: [HistoryEvent](), count: count)
        var markers = Array(repeating: Set<String>(), count: count)
        let sorted = events.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
        for event in sorted where event.timestamp >= day.start && event.timestamp < day.end {
            let index = Int(event.timestamp.timeIntervalSince(day.start) / 300)
            observations[index].append(event)
        }
        for project in trackedProjects {
            guard let date = project.lastCommitDate, date >= day.start, date < day.end else { continue }
            let index = Int(date.timeIntervalSince(day.start) / 300)
            markers[index].insert("Latest known commit · \(project.name) (\(project.activeBranch)) · \(project.lastCommitMessage)")
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = day.duration > 86400 ? "HH:mm xxx" : "HH:mm"
        return (0..<count).map { index in
            TimeMachineFrame(minuteOfDay: index * 5,
                timeString: formatter.string(from: day.start.addingTimeInterval(Double(index) * 300)),
                observations: observations[index], commitMarkers: markers[index].sorted())
        }
    }
    public static func summarize(timeline: [TimeMachineFrame]) -> DailyTimelineSummary {
        DailyTimelineSummary(observedIntervals: timeline.filter(\.hasObservations).count,
            observationCount: timeline.reduce(0) { $0 + $1.observations.count },
            latestKnownMarkers: Set(timeline.flatMap(\.commitMarkers)).count)
    }
}
