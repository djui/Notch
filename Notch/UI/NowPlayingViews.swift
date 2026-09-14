import AppKit
import SwiftUI

struct NowPlayingCollapsedView: View {
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.showNowPlaying, let item = nowPlaying.item {
            HStack(spacing: 6) {
                NowPlayingAppIcon(size: 15)
                Text(item.displayLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(item.isPlaying ? 0.92 : 0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.18), value: item.displayLine)
        }
    }
}

struct NowPlayingBarView: View {
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.showNowPlaying, let item = nowPlaying.item {
            HStack(spacing: 10) {
                NowPlayingAppIcon(size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? item.displayLine : item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    NowPlayingControlButton(systemName: "backward.fill") {
                        nowPlaying.skipPrevious()
                    }
                    NowPlayingControlButton(systemName: item.isPlaying ? "pause.fill" : "play.fill") {
                        nowPlaying.togglePlayPause()
                    }
                    NowPlayingControlButton(systemName: "forward.fill") {
                        nowPlaying.skipNext()
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct NowPlayingAppIcon: View {
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    var size: CGFloat

    var body: some View {
        Group {
            if let icon = nowPlaying.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct NowPlayingControlButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
