import SwiftUI

struct NotchView: View {
    @Environment(NotchHost.self) private var host
    @Environment(LiveActivityCenter.self) private var liveActivity
    @Environment(AgentActivityCenter.self) private var agents
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings

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

    private var showsNowPlaying: Bool {
        settings.showNowPlaying && nowPlaying.item != nil
    }

    /// Agents take the expanded notch while one is on the banner or waits on the user, and
    /// whenever nothing is playing.
    private var showsAgentInbox: Bool {
        guard settings.showAgents, !agents.inbox.isEmpty else { return false }
        if case .agent = liveActivity.current { return true }
        return agents.needsAttention || !showsNowPlaying
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
                    sideInset: host.geometry.contentSideInset(progress: morphProgress),
                    showsPlayer: !showsAgentInbox
                )
                    .frame(width: host.visualSize.width, height: host.visualSize.height)
                    .clipped()
                    .opacity(nowPlayingStageOpacity)
                if playerReveal > 0 {
                    expandedAlternative
                        .frame(width: host.visualSize.width, height: host.visualSize.height)
                        .clipped()
                        .opacity(playerReveal)
                        .allowsHitTesting(host.isExpanded && playerReveal > 0.9)
                }
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

    @ViewBuilder
    private var expandedAlternative: some View {
        if showsAgentInbox {
            AgentInboxView(
                sideInset: host.geometry.contentSideInset(progress: morphProgress),
                topInset: host.geometry.contentTopInset
            )
        } else if settings.showNowPlaying, nowPlaying.item == nil {
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, host.geometry.contentTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var collapsedSceneID: String {
        switch liveActivity.current {
        case .charging: "charging"
        case .lowPower: "lowPower"
        case .focus(let focus):
            "focus-\(focus.name)-\(focus.symbol)-\(focus.isOn)-\(focus.tintColorName)"
        case .agent(let agent):
            "agent-\(agent.sessionKey)-\(agent.label)"
        case nil: "nowPlaying"
        }
    }

}
