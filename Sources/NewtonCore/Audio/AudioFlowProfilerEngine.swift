import Foundation
import AppKit

public struct NowPlayingTrack: Identifiable, Sendable, Equatable, Codable {
    public var id: String { "\(title):\(artist)" }
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    public let source: String

    public init(title: String, artist: String, album: String = "", isPlaying: Bool = true, source: String = "System") {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.source = source
    }
}

public struct FlowTrackInsight: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let playMinutes: Int?
    public let avgKeystrokesPerMin: Int?
    public let avgFocusScore: Int?
    public let playCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        playMinutes: Int?,
        avgKeystrokesPerMin: Int?,
        avgFocusScore: Int?,
        playCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.playMinutes = playMinutes
        self.avgKeystrokesPerMin = avgKeystrokesPerMin
        self.avgFocusScore = avgFocusScore
        self.playCount = playCount
    }
}

public struct AudioFlowReport: Sendable, Equatable, Codable {
    public let topTracks: [FlowTrackInsight]
    public let topArtist: String
    public let topArtistTotalPlays: Int
    public let flowStateVelocityBoostPercent: Int?
    public let isLiveSession: Bool
    public let summary: String

    public static let empty = AudioFlowReport(
        topTracks: [],
        topArtist: "None",
        topArtistTotalPlays: 0,
        flowStateVelocityBoostPercent: nil,
        isLiveSession: false,
        summary: "No audio playback recorded."
    )

    public init(
        topTracks: [FlowTrackInsight],
        topArtist: String,
        topArtistTotalPlays: Int,
        flowStateVelocityBoostPercent: Int?,
        isLiveSession: Bool,
        summary: String
    ) {
        self.topTracks = topTracks
        self.topArtist = topArtist
        self.topArtistTotalPlays = topArtistTotalPlays
        self.flowStateVelocityBoostPercent = flowStateVelocityBoostPercent
        self.isLiveSession = isLiveSession
        self.summary = summary
    }
}

/// Pure Swift 6 Cognitive Flow & Audio Profiler Engine for Newton.
/// Correlates Apple Music & Spotify playback with developer typing cadence and focus depth.
public enum AudioFlowProfilerEngine: Sendable {

    /// Queries Apple Music or Spotify via standard non-blocking AppleScript.
    public static func fetchCurrentTrack() -> NowPlayingTrack? {
        // First check Apple Music
        if let music = queryMusicApp() {
            return music
        }
        // Then check Spotify
        if let spotify = querySpotifyApp() {
            return spotify
        }
        return nil
    }

    private static func queryMusicApp() -> NowPlayingTrack? {
        let scriptSource = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    return (get name of current track) & "|||" & (get artist of current track) & "|||" & (get album of current track)
                end if
            end tell
        end if
        return ""
        """

        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorInfo: NSDictionary?
        let resultDesc = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let output = resultDesc.stringValue, !output.isEmpty else { return nil }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        guard !title.isEmpty else { return nil }
        return NowPlayingTrack(title: title, artist: artist.isEmpty ? "Apple Music" : artist, album: album, isPlaying: true, source: "Apple Music")
    }

    private static func querySpotifyApp() -> NowPlayingTrack? {
        let scriptSource = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return (get name of current track) & "|||" & (get artist of current track) & "|||" & (get album of current track)
                end if
            end tell
        end if
        return ""
        """

        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorInfo: NSDictionary?
        let resultDesc = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let output = resultDesc.stringValue, !output.isEmpty else { return nil }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        guard !title.isEmpty else { return nil }
        return NowPlayingTrack(title: title, artist: artist.isEmpty ? "Spotify" : artist, album: album, isPlaying: true, source: "Spotify")
    }

    /// Analyzes recorded tracks and keystroke velocity to synthesize soundtrack to deep work.
    public static func analyzeAudioFlow(
        tracks: [NowPlayingTrack],
        keystrokes: Int = 0,
        focusMinutes: Int = 0
    ) -> AudioFlowReport {
        guard !tracks.isEmpty else { return .empty }

        var trackCounts: [String: (track: NowPlayingTrack, count: Int)] = [:]
        for t in tracks {
            let key = "\(t.title):\(t.artist)"
            if var entry = trackCounts[key] {
                entry.count += 1
                trackCounts[key] = entry
            } else {
                trackCounts[key] = (t, 1)
            }
        }

        let sorted = trackCounts.values.sorted { $0.count > $1.count }

        var insights: [FlowTrackInsight] = []
        for item in sorted.prefix(5) {
            insights.append(FlowTrackInsight(
                title: item.track.title,
                artist: item.track.artist,
                playMinutes: nil,
                avgKeystrokesPerMin: nil,
                avgFocusScore: nil,
                playCount: item.count
            ))
        }

        let topArtist = sorted.first?.track.artist ?? "Apple Music"
        let topArtistPlays = sorted.first?.count ?? 0


        let summary = "Now-playing metadata observed. Effects on typing velocity or productivity are unavailable."

        return AudioFlowReport(
            topTracks: insights,
            topArtist: topArtist,
            topArtistTotalPlays: topArtistPlays,
            flowStateVelocityBoostPercent: nil,
            isLiveSession: true,
            summary: summary
        )
    }
}
