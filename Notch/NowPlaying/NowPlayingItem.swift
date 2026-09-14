import AppKit
import Foundation

struct NowPlayingItem: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String?
    var appName: String?
    var isPlaying: Bool

    var displayLine: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedArtist.isEmpty { return trimmedTitle }
        if trimmedTitle.isEmpty { return trimmedArtist }
        return "\(trimmedArtist) - \(trimmedTitle)"
    }
}
