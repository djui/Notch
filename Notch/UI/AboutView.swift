import AppKit
import SwiftUI

enum AppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Notch"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionLabel: String {
        "Version \(shortVersion) (\(buildNumber))"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    static let homepageURL = URL(string: "https://github.com/djui/Notch")!
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text(AppInfo.versionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Link("Homepage", destination: AppInfo.homepageURL)
                .font(.callout)

            if !AppInfo.copyright.isEmpty {
                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 320)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }
}

@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "About \(AppInfo.name)"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            if size.width > 0, size.height > 0 {
                window.setContentSize(size)
            }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        centerOnScreen()
        window?.makeKeyAndOrderFront(nil)
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
