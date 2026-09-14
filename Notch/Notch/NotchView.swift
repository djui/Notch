import SwiftUI

struct NotchView: View {
    @Environment(NotchHost.self) private var host
    @Environment(LiveActivityCenter.self) private var liveActivity

    private var earRadius: CGFloat {
        switch host.geometry.layoutStyle {
        case .notch:
            return host.geometry.notchCornerRadii(expanded: host.isExpanded).ear
        case .island:
            return host.isExpanded ? host.geometry.expandedCornerRadius : host.visualSize.height / 2
        }
    }

    private var bottomRadius: CGFloat {
        switch host.geometry.layoutStyle {
        case .notch:
            return host.geometry.notchCornerRadii(expanded: host.isExpanded).bottom
        case .island:
            return earRadius
        }
    }

    private var shape: NotchShape {
        switch host.geometry.layoutStyle {
        case .notch:
            return NotchShape(style: .notch, earRadius: earRadius, bottomRadius: bottomRadius)
        case .island:
            let corner = host.isExpanded ? host.geometry.expandedCornerRadius : host.visualSize.height / 2
            return NotchShape(style: .island, earRadius: corner, bottomRadius: corner)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
        }
        .animation(.easeOut(duration: 0.18), value: host.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if host.isExpanded {
                expandedBody
                    .padding(.top, 8)
                    .transition(.opacity)
            } else {
                collapsedBody
                    .transition(.opacity)
            }
        }
        .modifier(TopAnchoredSize(size: host.visualSize))
        .animation(host.isExpanded ? Self.expandAnimation : Self.peekAnimation, value: host.visualSize)
        .clipShape(shape)
        .contentShape(shape)
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

    private static let expandAnimation = Animation.spring(response: 0.38, dampingFraction: 0.72)
    private static let peekAnimation = Animation.easeOut(duration: 0.16)

    /// Interpolates width/height in layout so the top-center edge stays put.
    /// Animating `.frame` directly lets SwiftUI move the view's center, which
    /// looks like a drop then zoom.
    private struct TopAnchoredSize: ViewModifier, Animatable {
        var size: CGSize

        var animatableData: AnimatablePair<CGFloat, CGFloat> {
            get { AnimatablePair(size.width, size.height) }
            set { size = CGSize(width: newValue.first, height: newValue.second) }
        }

        func body(content: Content) -> some View {
            content.frame(width: size.width, height: size.height, alignment: .top)
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

    @ViewBuilder
    private var expandedBody: some View {
        if let module = host.selectedModule {
            module.expandedView()
        } else {
            Color.clear
        }
    }
}
