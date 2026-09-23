import AppKit
import SwiftUI

/// One now-playing layout fitted to the notch. The compact line stays visible
/// and centered while the shape grows; the player fades in once there is room.
struct NowPlayingStageView: View {
    var playerReveal: CGFloat
    var sideInset: CGFloat

    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings
    @Environment(NotchHost.self) private var host

    var body: some View {
        if settings.showNowPlaying, let item = nowPlaying.item {
            ZStack {
                compactLine(item)
                    .opacity(compactOpacity)
                if playerReveal > 0 {
                    player(item)
                        .opacity(playerReveal)
                        .allowsHitTesting(host.isExpanded && playerReveal > 0.9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.easeOut(duration: 0.18), value: item.displayLine)
        }
    }

    private var compactOpacity: CGFloat {
        playerReveal <= 0 ? 1 : max(0, 1 - playerReveal / 0.45)
    }

    private func compactLine(_ item: NowPlayingItem) -> some View {
        HStack(spacing: 6) {
            NowPlayingArtworkView(size: 15, showsAppBadge: false)
                .layoutPriority(1)
            Text(item.displayLine)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(item.isPlaying ? 0.92 : 0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if item.isPlaying {
                EqualizerView(isPlaying: true, height: 11)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, compactInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// Clear the collapsed side wall without leaving a wide black gutter.
    private var compactInset: CGFloat {
        let radii = host.geometry.cornerRadii(progress: 0)
        switch host.geometry.layoutStyle {
        case .notch:
            return radii.ear + 6
        case .island:
            return 12
        }
    }

    private func player(_ item: NowPlayingItem) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NowPlayingArtworkView(size: 52, showsAppBadge: true)
                Button {
                    host.openNowPlayingSource()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(
                            text: item.displayTitle.isEmpty ? item.displayLine : item.displayTitle,
                            font: .system(size: 15, weight: .semibold),
                            color: .white.opacity(0.94),
                            lineHeight: 18
                        )
                        if !item.artist.isEmpty {
                            MarqueeText(
                                text: item.artist,
                                font: .system(size: 13, weight: .medium),
                                color: .white.opacity(0.5),
                                lineHeight: 16
                            )
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(sourceHelp(for: item))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)

                if item.isPlaying {
                    EqualizerView(isPlaying: true, height: 16)
                        .layoutPriority(1)
                }
            }

            if item.duration > 1 {
                progress(item)
            }

            HStack(spacing: 28) {
                NowPlayingControlButton(systemName: "backward.fill", pointSize: 18) {
                    nowPlaying.skipPrevious()
                }
                NowPlayingControlButton(
                    systemName: item.isPlaying ? "pause.fill" : "play.fill",
                    pointSize: 24
                ) {
                    nowPlaying.togglePlayPause()
                }
                NowPlayingControlButton(systemName: "forward.fill", pointSize: 18) {
                    nowPlaying.skipNext()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, sideInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func progress(_ item: NowPlayingItem) -> some View {
        if item.isPlaying {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                progressBar(item, at: context.date)
            }
        } else {
            progressBar(item, at: item.positionDate)
        }
    }

    private func progressBar(_ item: NowPlayingItem, at date: Date) -> some View {
        let elapsed = item.currentElapsed(at: date)
        let remaining = item.currentRemaining(at: date)
        let fraction = item.duration > 0 ? min(1, max(0, elapsed / item.duration)) : 0
        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.22))
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
            HStack {
                Text(Self.clock(elapsed))
                Spacer(minLength: 8)
                Text("-\(Self.clock(remaining))")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func sourceHelp(for item: NowPlayingItem) -> String {
        let name = item.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { return "Show playing app" }
        return "Show in \(name)"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Scrolls long titles back and forth inside the width the parent offers.
/// Takes the offered width (does not expand to the string’s ideal size), which
/// is what makes overflow detectable and keeps the text inside the notch.
private struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color
    var lineHeight: CGFloat
    /// Points per second while traveling.
    var speed: CGFloat = 28
    var endPause: TimeInterval = 0.9

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var runID = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        Color.clear
            .frame(height: lineHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: geo.size.width
                            )
                        }
                    )
                    .offset(x: offset)
            }
            .clipped()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: MarqueeContainerWidthKey.self,
                        value: geo.size.width
                    )
                }
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
            .onPreferenceChange(MarqueeContainerWidthKey.self) { width in
                if abs(containerWidth - width) > 0.5 {
                    containerWidth = width
                    restart()
                }
            }
            .onChange(of: text) { _, _ in restart() }
            .task(id: runID) {
                await runMarquee()
            }
    }

    private func restart() {
        offset = 0
        runID &+= 1
    }

    @MainActor
    private func runMarquee() async {
        offset = 0
        // Wait for preferences + a beat at the start.
        try? await Task.sleep(for: .seconds(endPause))
        while !Task.isCancelled {
            let distance = overflow
            guard distance > 1 else {
                offset = 0
                // Keep the task alive so a later width change can restart via runID.
                try? await Task.sleep(for: .seconds(0.5))
                continue
            }
            let duration = max(1.2, Double(distance) / Double(speed))
            withAnimation(.easeInOut(duration: duration)) {
                offset = -distance
            }
            try? await Task.sleep(for: .seconds(duration + endPause))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: duration)) {
                offset = 0
            }
            try? await Task.sleep(for: .seconds(duration + endPause))
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    var pointSize: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: pointSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
