import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case app
    case clipboard
    case media
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .app: "App"
        case .clipboard: "Clipboard"
        case .media: "Media Playback"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .app: "gearshape"
        case .clipboard: "doc.on.clipboard"
        case .media: "play.circle"
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
        case .clipboard:
            ClipboardSettingsPane()
        case .media:
            MediaPlaybackSettingsPane()
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
                HStack {
                    Text("Open Notch")
                    Spacer()
                    HotkeyRecorder(
                        shortcut: Bindable(settings).openShortcut,
                        defaultShortcut: .defaultOpen
                    )
                }
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

private struct ClipboardSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var isAccessibilityTrusted = PasteService.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Pause clipboard capture", isOn: Bindable(settings).isPaused)
                Stepper(value: Bindable(settings).historyLimit, in: 20...2000, step: 20) {
                    Text("Keep \(settings.historyLimit) items")
                }
                Text("Pinned items are kept even when the limit is reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Paste as Plain Text")
                    Spacer()
                    HotkeyRecorder(
                        shortcut: Bindable(settings).plainPasteShortcut,
                        defaultShortcut: .defaultPlainPaste,
                        allowShiftOnly: true
                    )
                }
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if isAccessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text("Required to paste")
                            .foregroundStyle(.orange)
                    }
                }
                if !isAccessibilityTrusted {
                    Button("Request Accessibility Access") {
                        PasteService.requestTrust()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refreshAccessibilityTrust)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityTrust()
        }
        .task {
            while !Task.isCancelled {
                refreshAccessibilityTrust()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshAccessibilityTrust() {
        isAccessibilityTrusted = PasteService.isTrusted
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
