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

    /// Player content waits until the notch is tall enough to hold it.
    private var playerReveal: CGFloat {
        min(1, max(0, (morphProgress - 0.68) / 0.26))
    }

    /// Live-activity banners stay put until the player has room to replace them.
    private var nowPlayingStageOpacity: CGFloat {
        liveActivity.current == nil ? 1 : playerReveal
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
        ZStack {
            shape.fill(Color.black)
            ZStack {
                if let activity = liveActivity.current {
                    LiveActivityView(activity: activity)
                        .opacity(1 - nowPlayingStageOpacity)
                        .allowsHitTesting(false)
                }
                NowPlayingStageView(
                    playerReveal: playerReveal,
                    sideInset: host.geometry.contentSideInset(progress: morphProgress)
                )
                    .opacity(nowPlayingStageOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.32), value: collapsedSceneID)
        }
        .frame(width: host.visualSize.width, height: host.visualSize.height)
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

}
