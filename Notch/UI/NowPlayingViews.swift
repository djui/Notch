import AppKit
import SwiftUI

struct NowPlayingCollapsedView: View {
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.showNowPlaying, let item = nowPlaying.item {
            HStack(spacing: 6) {
                NowPlayingArtworkView(size: 15, showsAppBadge: false)
                Text(item.displayLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(item.isPlaying ? 0.92 : 0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isPlaying {
                    EqualizerView(isPlaying: true, height: 11)
                }
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
    @Environment(NotchHost.self) private var host

    var body: some View {
        if settings.showNowPlaying, let item = nowPlaying.item {
            HStack(spacing: 10) {
                NowPlayingArtworkView(size: 34, showsAppBadge: true)
                Button {
                    host.openNowPlayingSource()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayTitle.isEmpty ? item.displayLine : item.displayTitle)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(sourceHelp(for: item))

                if item.isPlaying {
                    EqualizerView(isPlaying: true, height: 14)
                }

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

    private func sourceHelp(for item: NowPlayingItem) -> String {
        let name = item.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { return "Show playing app" }
        return "Show in \(name)"
    }
}

private struct NowPlayingArtworkView: View {
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    var size: CGFloat
    var showsAppBadge: Bool

    var body: some View {
        let media = nowPlaying.artwork ?? nowPlaying.appIcon
        ZStack(alignment: .bottomTrailing) {
            artworkImage(media, size: size)
            if showsAppBadge, nowPlaying.artwork != nil, let appIcon = nowPlaying.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badgeSize, height: badgeSize)
                    .clipShape(RoundedRectangle(cornerRadius: badgeSize * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: badgeSize * 0.22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size, height: size)
        .padding(.trailing, showsAppBadge ? 3 : 0)
        .padding(.bottom, showsAppBadge ? 3 : 0)
    }

    private var badgeSize: CGFloat { max(12, size * 0.42) }

    @ViewBuilder
    private func artworkImage(_ image: NSImage?, size: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
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
