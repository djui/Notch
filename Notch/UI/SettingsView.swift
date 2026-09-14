import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section("General") {
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
                Toggle("Show Now Playing in notch", isOn: Bindable(settings).showNowPlaying)
                Toggle("Pause clipboard capture", isOn: Bindable(settings).isPaused)
                HStack {
                    Text("Open Notch")
                    Spacer()
                    HotkeyRecorder(
                        shortcut: Bindable(settings).openShortcut,
                        defaultShortcut: .defaultOpen
                    )
                }
            }

            Section("History") {
                Stepper(value: Bindable(settings).historyLimit, in: 20...2000, step: 20) {
                    Text("Keep \(settings.historyLimit) items")
                }
                Text("Pinned items are kept even when the limit is reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pasting") {
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
                    Text(PasteService.isTrusted ? "Granted" : "Required to paste")
                        .foregroundStyle(PasteService.isTrusted ? Color.secondary : Color.orange)
                }
                if !PasteService.isTrusted {
                    Button("Request Accessibility Access") {
                        PasteService.requestTrust()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
        .navigationTitle("Notch Settings")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }
}
