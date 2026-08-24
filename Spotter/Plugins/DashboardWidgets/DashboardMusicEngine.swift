import Foundation

enum DashboardMusicState: String, Equatable, Sendable {
    case stopped
    case paused
    case playing

    var isPlaying: Bool { self == .playing }
}

struct DashboardTrack: Equatable, Sendable {
    /// Music's persistent ID: stable for the track, so artwork is fetched once rather than per tick.
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
}

/// Everything the card draws. `isRunning` is false when Music is not open at all, which is not the
/// same as stopped — the card says so instead of implying a player that is merely idle.
struct DashboardMusicSnapshot: Equatable, Sendable {
    var isRunning: Bool
    var state: DashboardMusicState
    var track: DashboardTrack?

    static let idle = DashboardMusicSnapshot(isRunning: false, state: .stopped, track: nil)

    var isPlaying: Bool { isRunning && state.isPlaying }
}

enum DashboardMusicEngine {
    /// ASCII unit separator: a track title can hold anything printable, so the delimiter has to be
    /// something a tag never contains.
    static let fieldSeparator = "\u{1F}"

    /// Parses the reader script's one line. Anything unexpected reads as stopped rather than
    /// throwing: the card's job is to show what is playing, and "nothing" is a valid answer.
    static func snapshot(fromScriptOutput output: String) -> DashboardMusicSnapshot {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = trimmed.components(separatedBy: fieldSeparator)
        guard fields.count >= 6, let state = DashboardMusicState(rawValue: fields[0].lowercased()),
            state != .stopped
        else {
            return DashboardMusicSnapshot(isRunning: true, state: .stopped, track: nil)
        }
        let title = fields[2].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            return DashboardMusicSnapshot(isRunning: true, state: .stopped, track: nil)
        }
        return DashboardMusicSnapshot(
            isRunning: true,
            state: state,
            track: DashboardTrack(
                id: fields[1],
                title: title,
                artist: fields[3].trimmingCharacters(in: .whitespaces),
                album: fields[4].trimmingCharacters(in: .whitespaces),
                duration: max(0, Double(fields[5]) ?? 0)))
    }

    /// The second line of the card. Album is dropped rather than truncated into the artist: at this
    /// size one of them has to go, and the artist is what identifies the track.
    static func subtitle(for track: DashboardTrack) -> String {
        track.artist.isEmpty ? track.album : track.artist
    }

    /// What the card says when there is nothing to draw, so an empty square never reads as broken.
    static func restingLine(isRunning: Bool) -> String {
        isRunning ? "Nothing playing" : "Music is not open"
    }
}
