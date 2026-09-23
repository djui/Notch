import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case accessibility
    case media
    case browsers

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}

struct PermissionOnboardingView: View {
    var onFinished: () -> Void

    @State private var step: OnboardingStep = .accessibility

    var body: some View {
        VStack(spacing: 22) {
            hero
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            appStrip

            Text("Choose “Allow” once Apple requests permission to interact on behalf of Notch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer(minLength: 8)

            Button(action: continueTapped) {
                Text("Continue")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 420, height: 520)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .overlay {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 72, height: 72)
                    }
                badge
                    .offset(x: 6, y: 6)
            }

            Capsule()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 120, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 120 * step.progress)
                }
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var badge: some View {
        Image(systemName: badgeSymbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(badgeColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            }
    }

    private var appStrip: some View {
        Group {
            if step == .accessibility {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 42, height: 42)
                        Text("Now Playing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(stepApps.enumerated()), id: \.offset) { index, target in
                        if index > 0 {
                            Divider()
                                .frame(height: 48)
                        }
                        VStack(spacing: 8) {
                            Image(nsImage: target.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 42, height: 42)
                            Text(target.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var title: String {
        switch step {
        case .accessibility:
            "Notch needs your permission to bring the playing app forward."
        case .media:
            "Notch needs your permission to control and display your playing music."
        case .browsers:
            "Notch needs your permission to identify tabs with playing audio."
        }
    }

    private var badgeSymbol: String {
        switch step {
        case .accessibility: "hand.raised.fill"
        case .media: "music.note"
        case .browsers: "safari"
        }
    }

    private var badgeColor: Color {
        switch step {
        case .accessibility: Color.mint
        case .media: Color.pink
        case .browsers: Color.blue
        }
    }

    private var stepApps: [AutomationTarget] {
        switch step {
        case .accessibility:
            []
        case .media:
            [.music, .spotify].filter(\.isInstalled)
        case .browsers:
            [.safari, .chrome].filter(\.isInstalled)
        }
    }

    private func continueTapped() {
        switch step {
        case .accessibility:
            PermissionStatus.requestAccessibility()
        case .media:
            PermissionStatus.requestAutomation(.music)
            PermissionStatus.requestAutomation(.spotify)
        case .browsers:
            PermissionStatus.requestAutomation(.safari)
            PermissionStatus.requestAutomation(.chrome)
        }

        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.22)) {
                step = next
            }
        } else {
            onFinished()
        }
    }
}

@MainActor
final class PermissionOnboardingController: NSObject, NSWindowDelegate {
    static let shared = PermissionOnboardingController()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let root = PermissionOnboardingView { [weak self] in
                self?.finish()
            }
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Notch Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .normal
            window.delegate = self
            window.setContentSize(NSSize(width: 420, height: 520))
            self.window = window
        }
        AccessoryWindowPolicy.refresh()
        NSApp.activate(ignoringOtherApps: true)
        centerOnScreen()
        window?.makeKeyAndOrderFront(nil)
        AppModel.shared.host.visibilityRefresh()
    }

    func restoreKey() {
        guard isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(closeWindow: false)
    }

    private func finish(closeWindow: Bool = true) {
        if closeWindow {
            window?.close()
        }
        DispatchQueue.main.async {
            AccessoryWindowPolicy.refresh()
            AppModel.shared.host.visibilityRefresh()
        }
    }

    private func centerOnScreen() {
        guard let window else { return }
        let screen = NotchGeometry.preferredScreen(preferMouse: false)
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrameOrigin(frame.origin)
    }
}
