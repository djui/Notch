import SwiftUI

struct NotchView: View {
    @Environment(NotchHost.self) private var host
    @Environment(LiveActivityCenter.self) private var liveActivity
    @Environment(AgentActivityCenter.self) private var agents
    @Environment(NowPlayingMonitor.self) private var nowPlaying
    @Environment(ShelfStore.self) private var shelf
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

    /// Collapsed content fades out as the expanded stage fades in.
    private var collapsedOpacity: CGFloat {
        1 - playerReveal
    }

    private var sideInset: CGFloat {
        host.geometry.contentSideInset(progress: morphProgress)
    }

    /// Collapsed content avoids the camera housing when the notch has wings.
    private var centerGap: CGFloat {
        host.showsWings ? host.geometry.cameraGap : 0
    }

    private var showsNowPlaying: Bool {
        settings.showNowPlaying && nowPlaying.item != nil
    }

    // MARK: - Stages

    private var availableStages: [ExpandedStage] {
        var stages: [ExpandedStage] = []
        if settings.showAgents, !agents.inbox.isEmpty { stages.append(.agents) }
        if settings.showMeetings, liveActivity.meetings.upcoming != nil { stages.append(.meeting) }
        if showsNowPlaying { stages.append(.nowPlaying) }
        if settings.showShelf, !shelf.items.isEmpty || host.isDropTargeted { stages.append(.shelf) }
        return stages
    }

    /// What the notch opens to: whatever the banner is about, then anything waiting on the
    /// user, then media, agents, the meeting, and the shelf.
    private var preferredStage: ExpandedStage? {
        let stages = availableStages
        switch liveActivity.current {
        case .agent where stages.contains(.agents): return .agents
        case .meeting where stages.contains(.meeting): return .meeting
        default: break
        }
        if agents.needsAttention, stages.contains(.agents) { return .agents }
        return [.nowPlaying, .agents, .meeting, .shelf].first(where: stages.contains)
    }

    private var stage: ExpandedStage? {
        if let selected = host.selectedStage, availableStages.contains(selected) {
            return selected
        }
        return preferredStage
    }

    /// Room for the stage buttons, or at least for the camera housing.
    private var stageBarHeight: CGFloat {
        max(NotchGeometry.stageBarHeight, host.geometry.contentTopInset)
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .tint(.white)
        .onChange(of: host.isExpanded) { _, expanded in
            // Freeze the choice so the stage doesn't switch under the pointer.
            if expanded, host.selectedStage == nil {
                host.selectedStage = preferredStage
            }
        }
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
                collapsedContent
                    .opacity(collapsedOpacity)
                    .allowsHitTesting(false)
                NowPlayingStageView(
                    playerReveal: stage == .nowPlaying ? playerReveal : 0,
                    sideInset: sideInset,
                    showsPlayer: stage == .nowPlaying,
                    topInset: stageBarHeight - 12,
                    centerGap: centerGap
                )
                    .frame(width: host.visualSize.width, height: host.visualSize.height)
                    .clipped()
                    .opacity(stage == .nowPlaying ? (liveActivity.current == nil ? 1 : playerReveal) : 0)
                if playerReveal > 0 {
                    expandedStage
                        .frame(width: host.visualSize.width, height: host.visualSize.height)
                        .clipped()
                        .opacity(playerReveal)
                        .allowsHitTesting(host.isExpanded && playerReveal > 0.9)
                    stageBar
                        .frame(width: host.visualSize.width, height: host.visualSize.height, alignment: .top)
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
        .onDrop(
            of: settings.showShelf ? [.fileURL] : [],
            isTargeted: Binding(get: { host.isDropTargeted }, set: { host.setDropTargeted($0) })
        ) { providers in
            shelf.accept(providers)
        }
        .contextMenu {
            Button("Settings…") { host.openSettings() }
            Divider()
            Button("Relaunch Notch") { NSApp.relaunch() }
            Button("Quit Notch") { NSApp.terminate(nil) }
        }
    }

    /// A banner, else media, else a running agent. Media draws its own compact line.
    @ViewBuilder
    private var collapsedContent: some View {
        if let activity = liveActivity.current {
            LiveActivityView(activity: activity, centerGap: centerGap)
        } else if !showsNowPlaying, settings.showAgents, settings.agentShowRunning,
                  let running = agents.runningSession {
            AgentRunLine(session: running, centerGap: centerGap)
        } else if showsNowPlaying, stage != .nowPlaying {
            // The media line lives in NowPlayingStageView, which is hidden while another stage
            // is chosen; keep it visible while collapsed.
            NowPlayingStageView(playerReveal: 0, sideInset: sideInset, showsPlayer: false, centerGap: centerGap)
        }
    }

    @ViewBuilder
    private var expandedStage: some View {
        switch stage {
        case .agents:
            AgentInboxView(sideInset: sideInset, topInset: stageBarHeight)
        case .meeting:
            if let meeting = liveActivity.meetings.upcoming {
                MeetingCardView(meeting: meeting, sideInset: sideInset)
                    .padding(.top, stageBarHeight)
            }
        case .shelf:
            ShelfView(sideInset: sideInset)
                .padding(.top, stageBarHeight)
        case .nowPlaying:
            EmptyView()
        case nil:
            Text(settings.showShelf ? "Nothing playing. Drop files here to keep them." : "Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, host.geometry.contentTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Buttons for switching stages, left of the camera housing. Hidden with one stage.
    @ViewBuilder
    private var stageBar: some View {
        let stages = availableStages
        if stages.count > 1 {
            HStack(spacing: 2) {
                ForEach(stages) { item in
                    Button {
                        host.selectedStage = item
                    } label: {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(item == stage ? 0.95 : 0.4))
                            .frame(width: 24, height: 20)
                            .background(
                                Color.white.opacity(item == stage ? 0.14 : 0),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, sideInset - 4)
            .padding(.top, 4)
            .frame(height: stageBarHeight, alignment: .top)
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
        case .meeting(let meeting): "meeting-\(meeting.id)"
        case .privacy(let privacy): "privacy-\(privacy.label)"
        case .level(let level): "level-\(level.symbolName.hasPrefix("sun") ? "brightness" : "volume")"
        case .headphones(let headphones): "headphones-\(headphones.name)"
        case nil: "nowPlaying"
        }
    }
}
