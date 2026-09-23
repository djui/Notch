import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case app
    case media
    case permissions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .app: "App"
        case .media: "Media Playback"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .app: "gearshape"
        case .media: "play.circle"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var pane: SettingsPane? = .app

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 188, max: 220)
        } detail: {
            SettingsDetailView(pane: pane ?? .app)
                .navigationTitle((pane ?? .app).title)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 640, minHeight: 400)
        .frame(width: 680, height: 440)
        .navigationTitle("Notch Settings")
    }
}

private struct SettingsDetailView: View {
    var pane: SettingsPane

    var body: some View {
        switch pane {
        case .app:
            AppSettingsPane()
        case .media:
            MediaPlaybackSettingsPane()
        case .permissions:
            PermissionsSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }
}

private struct AppSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: Bindable(settings).layoutStyle) {
                    ForEach(NotchLayoutStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if settings.loginItemBlocked {
                    Text("macOS is waiting for approval. Enable Notch in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") {
                        settings.openLoginItemsSettings()
                    }
                }
                Toggle("Show menu bar icon", isOn: Bindable(settings).showStatusItem)
                Toggle("Open on hover", isOn: Bindable(settings).openOnHover)
                Toggle("Show during fullscreen, Mission Control, and screenshots", isOn: Bindable(settings).showInSystemSurfaces)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }
}

private struct MediaPlaybackSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                Toggle("Show Now Playing in notch", isOn: Bindable(settings).showNowPlaying)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct PermissionsSettingsPane: View {
    @State private var center = PermissionCenter()

    var body: some View {
        Form {
            Section("Paste") {
                permissionStatusRow(
                    title: "Accessibility",
                    detail: "Required to bring the playing app forward.",
                    state: center.accessibilityTrusted ? .granted : .denied
                )
                if !center.accessibilityTrusted {
                    Text("macOS grants Accessibility per app copy. Xcode Debug and a released Notch.app are different binaries. Enable the entry that matches this build, then relaunch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.bundlePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    HStack {
                        Button("Request Access") {
                            center.requestAccessibility()
                        }
                        Button("Open System Settings") {
                            PermissionStatus.openAccessibilitySettings()
                        }
                        Button("Relaunch Notch") {
                            NSApp.relaunch()
                        }
                    }
                }
            }

            Section("Focus") {
                permissionStatusRow(
                    title: "Full Disk Access",
                    detail: "Required to show the current Focus mode name and icon.",
                    state: center.focusDatabaseReadable ? .granted : .denied
                )
                if !center.focusDatabaseReadable {
                    Button("Open System Settings") {
                        PermissionStatus.openFullDiskAccessSettings()
                    }
                }
            }

            Section("Automation") {
                ForEach(AutomationTarget.allCases) { target in
                    let state = center.automation[target] ?? .notDetermined
                    permissionStatusRow(
                        title: target.title,
                        detail: automationDetail(target),
                        state: state
                    )
                    if state != .granted, state != .unavailable {
                        Button("Request \(target.title)") {
                            center.requestAutomation(target)
                        }
                    }
                }
                Button("Open Automation Settings") {
                    PermissionStatus.openAutomationSettings()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { center.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            center.refresh()
        }
        .task {
            while !Task.isCancelled {
                center.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func automationDetail(_ target: AutomationTarget) -> String {
        switch target {
        case .music, .spotify:
            "Now Playing artwork and control."
        case .safari, .chrome:
            "Identify tabs with playing audio."
        }
    }

    private func permissionStatusRow(title: String, detail: String, state: PermissionState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusLabel(state)
        }
    }

    @ViewBuilder
    private func statusLabel(_ state: PermissionState) -> some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .denied:
            Text("Not granted")
                .foregroundStyle(.orange)
        case .notDetermined:
            Text("Not determined")
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("Not installed")
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppInfo.versionLabel)
                Button("About Notch…") {
                    AboutWindowController.shared.show()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
