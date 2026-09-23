import AppKit
import Foundation

struct NowPlayingItem: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String?
    var appName: String?
    var isPlaying: Bool
    /// Track length in seconds. Zero when MediaRemote has no duration.
    var duration: TimeInterval
    /// Playback position, in seconds, at `positionDate`.
    var elapsed: TimeInterval
    /// When `elapsed` was sampled. While playing, the bar advances from this instant.
    var positionDate: Date

    var displayTitle: String {
        Self.cleanedTitle(title)
    }

    var isWebSource: Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return Self.isBrowserBundle(bundleIdentifier)
    }

    var isSpotifyApp: Bool {
        bundleIdentifier == "com.spotify.client"
    }

    var artworkKey: String {
        "\(bundleIdentifier ?? "")|\(title)|\(artist)|\(album)"
    }

    func currentElapsed(at date: Date = .now) -> TimeInterval {
        let advanced = isPlaying ? date.timeIntervalSince(positionDate) : 0
        let position = elapsed + max(0, advanced)
        guard duration > 0 else { return max(0, position) }
        return min(duration, max(0, position))
    }

    func currentRemaining(at date: Date = .now) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return max(0, duration - currentElapsed(at: date))
    }

    var displayLine: String {
        let trimmedTitle = displayTitle
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedArtist.isEmpty { return trimmedTitle }
        if trimmedTitle.isEmpty { return trimmedArtist }
        return "\(trimmedTitle) (\(trimmedArtist))"
    }

    static func isBrowserBundle(_ id: String) -> Bool {
        let prefixes = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.brave.Browser",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "com.kagi.kagimacOS",
            "org.chromium.Chromium",
            "com.orionbrowser.Orion",
        ]
        return prefixes.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    private static func cleanedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [" - YouTube", " | YouTube", " - YouTube Music"]
        for suffix in suffixes {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title = String(title.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return title
    }
}
