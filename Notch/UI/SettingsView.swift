import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case app
    case media
    case liveActivities
    case agents
    case permissions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .app: "App"
        case .media: "Media Playback"
        case .liveActivities: "Live Activities"
        case .agents: "Coding Agents"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .app: "gearshape"
        case .media: "play.circle"
        case .liveActivities: "bolt.circle"
        case .agents: "bell.badge"
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
        case .liveActivities:
            LiveActivitiesSettingsPane()
        case .agents:
            AgentsSettingsPane()
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
                Toggle("Tap the trackpad when the pointer enters the notch", isOn: Bindable(settings).hoverHaptics)
                Toggle("Keep files dropped on the notch", isOn: Bindable(settings).showShelf)
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

private struct LiveActivitiesSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LiveActivityCenter.self) private var liveActivity

    var body: some View {
        Form {
            Section {
                Toggle("Show charging in notch", isOn: Bindable(settings).showBattery)
                Text("Includes Low Power Mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show Focus in notch", isOn: Bindable(settings).showFocus)
                Toggle("Show when the microphone or camera turns on", isOn: Bindable(settings).showPrivacy)
                Toggle("Show headphones connecting, with battery", isOn: Bindable(settings).showAudioDevices)
                Toggle("Show volume and brightness changes", isOn: Bindable(settings).showLevels)
                Text("The system's own volume and brightness indicator still appears. Brightness needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Count down to the next meeting", isOn: Bindable(settings).showMeetings)
                Text("Five minutes ahead, with a Join button for Zoom, Meet, Teams, Webex, and FaceTime links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.showMeetings, liveActivity.meetings.accessDenied {
                    Text("Notch doesn't have access to your calendars.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Open Calendar Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct AgentsSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AgentActivityCenter.self) private var agents
    @State private var statuses: [CodingAgent: AgentHookInstaller.Status] = [:]
    @State private var hookError: String?
    @State private var commandLineInstalled = false

    private var commandLineHint: String {
        if let link = AgentHookInstaller.commandLineLinkURL() {
            return "Linked into \(link.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
        }
        return "~/.config/notch/notch; add it to your PATH"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show coding agents in notch", isOn: Bindable(settings).showAgents)
                if let error = agents.serverError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Claude Code, Cursor, and Codex report to Notch through hooks. Events stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notify when an agent") {
                Toggle("Needs your attention", isOn: Bindable(settings).agentAttention)
                Toggle("Finishes", isOn: Bindable(settings).agentFinished)
                Toggle("Fails", isOn: Bindable(settings).agentErrors)
                Toggle("Starts, compacts, or ends a session", isOn: Bindable(settings).agentOther)
                Toggle("Play sounds", isOn: Bindable(settings).agentSounds)
                Toggle("Stay quiet while the agent's app is in front", isOn: Bindable(settings).agentQuietWhenFrontmost)
                Text("Requests, failures, and the notch command always show.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show a timer while an agent works", isOn: Bindable(settings).agentShowRunning)
            }
            .disabled(!settings.showAgents)

            Section("Answer from the notch") {
                Toggle("Allow or deny permission prompts from the notch", isOn: Bindable(settings).agentApprovals)
                Text("While Claude Code or Codex runs in the background, Notch holds a permission prompt for up to 25 seconds so you can answer it here. After that, or when the agent's app is in front, the agent asks as usual. Needs the hooks below to be installed or repaired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Questions from agents in iTerm2 or Terminal can be answered with the reply button in the expanded notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.showAgents)

            Section {
                ForEach(CodingAgent.hookable) { agent in
                    hookRow(agent)
                }
                if let hookError {
                    Text(hookError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Hooks")
            } footer: {
                Text("Notch adds its hook after yours and keeps the previous file as <name>.notch-backup. Codex runs new hooks once you trust them with /hooks. Cursor has no hook for approval prompts, so it reports finished and failed runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("notch command")
                        Text(commandLineHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if commandLineInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                        Button("Remove") {
                            AgentHookInstaller.uninstallCommandLineTool()
                            refresh()
                        }
                    } else {
                        Button("Install") {
                            update { try AgentHookInstaller.installCommandLineTool() }
                        }
                    }
                }
            } header: {
                Text("Any command")
            } footer: {
                Text("notch done \"Tests passed\", notch fail, notch ask, or notch run make test to report how a command went.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Send Test Notification") {
                    agents.sendTestNotification()
                }
                .disabled(!settings.showAgents)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func hookRow(_ agent: CodingAgent) -> some View {
        let status = statuses[agent] ?? .notInstalled
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title)
                Text(agent.hookConfigDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            hookStatusLabel(status)
            switch status {
            case .installed:
                Button("Remove") { update { try AgentHookInstaller.uninstall(agent) } }
            case .partial:
                Button("Repair") { update { try AgentHookInstaller.install(agent) } }
            case .notInstalled, .notDetected:
                Button("Install") { update { try AgentHookInstaller.install(agent) } }
            case .unreadable:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func hookStatusLabel(_ status: AgentHookInstaller.Status) -> some View {
        switch status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .partial:
            Text("Incomplete")
                .foregroundStyle(.orange)
        case .notInstalled:
            Text("Not installed")
                .foregroundStyle(.secondary)
        case .notDetected:
            Text("Not found")
                .foregroundStyle(.tertiary)
        case .unreadable:
            Text("Config is not valid JSON")
                .foregroundStyle(.red)
        }
    }

    private func update(_ change: () throws -> Void) {
        do {
            try change()
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        var next: [CodingAgent: AgentHookInstaller.Status] = [:]
        for agent in CodingAgent.hookable {
            next[agent] = AgentHookInstaller.status(for: agent)
        }
        statuses = next
        commandLineInstalled = AgentHookInstaller.commandLineToolInstalled()
    }
}

private struct PermissionsSettingsPane: View {
    @State private var center = PermissionCenter()

    var body: some View {
        Form {
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
