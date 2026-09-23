import SwiftUI

struct NotchView: View {
    @Environment(NotchHost.self) private var host
    @Environment(LiveActivityCenter.self) private var liveActivity

    private var morphProgress: CGFloat {
        host.geometry.morphProgress(visualSize: host.visualSize)
    }

    private var shape: NotchShape {
        let radii = host.geometry.cornerRadii(progress: morphProgress)
        return NotchShape(
            style: host.geometry.layoutStyle,
            earRadius: radii.ear,
            bottomRadius: radii.bottom
        )
    }

    private var expandedContentOpacity: CGFloat {
        min(1, max(0, (morphProgress - 0.2) / 0.5))
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var notchBody: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: host.geometry.topHitPadding)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            visualNotch
        }
    }

    private var visualNotch: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if morphProgress < 0.8 {
                collapsedBody
                    .opacity(max(0, 1 - morphProgress * 2))
            }
            if host.isExpanded || morphProgress > 0.05 {
                expandedBody
                    .padding(.top, 8)
                    .frame(
                        width: host.geometry.expandedSize.width,
                        height: host.geometry.expandedSize.height,
                        alignment: .top
                    )
                    .opacity(expandedContentOpacity)
                    .allowsHitTesting(host.isExpanded && morphProgress > 0.9)
            }
        }
        .frame(width: host.visualSize.width, height: host.visualSize.height, alignment: .top)
        .clipShape(shape)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                host.mouseEntered()
            } else {
                host.mouseExited()
            }
        }
        .contextMenu {
            Button("Settings…") { host.openSettings() }
            Divider()
            Button("Relaunch Notch") { NSApp.relaunch() }
            Button("Quit Notch") { NSApp.terminate(nil) }
        }
    }

    private var collapsedSceneID: String {
        switch liveActivity.current {
        case .charging: "charging"
        case .lowPower: "lowPower"
        case .focus(let focus):
            "focus-\(focus.name)-\(focus.symbol)-\(focus.isOn)-\(focus.tintColorName)"
        case nil: "nowPlaying"
        }
    }

    private var collapsedBody: some View {
        ZStack {
            if let activity = liveActivity.current {
                LiveActivityView(activity: activity)
                    .transition(.opacity)
            } else {
                NowPlayingCollapsedView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: collapsedSceneID)
    }

    private var expandedBody: some View {
        NowPlayingBarView()
    }
}
