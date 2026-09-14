import SwiftUI

struct NotchView: View {
    @Environment(NotchHost.self) private var host
    @Environment(AppSettings.self) private var settings

    private var earRadius: CGFloat {
        host.isExpanded ? max(8, host.geometry.earRadius) : host.geometry.earRadius
    }

    private var bottomRadius: CGFloat {
        host.isExpanded ? 10 : 8
    }

    private var shape: NotchShape {
        NotchShape(earRadius: earRadius, bottomRadius: bottomRadius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if host.isExpanded {
                expandedBody
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .frame(width: host.visualSize.width, height: host.visualSize.height)
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
            Button(settings.showStatusItem ? "Hide Menu Bar Icon" : "Show Menu Bar Icon") {
                settings.showStatusItem.toggle()
            }
            Divider()
            Button("Quit Notch") { NSApp.terminate(nil) }
        }
        .animation(Self.expandAnimation, value: host.visualSize)
        .animation(.easeOut(duration: 0.18), value: host.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private static let expandAnimation = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.36)

    @ViewBuilder
    private var expandedBody: some View {
        if let module = host.selectedModule {
            module.expandedView()
        } else {
            Color.clear
        }
    }
}
