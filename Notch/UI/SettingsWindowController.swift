import AppKit
import SwiftUI

enum AccessoryWindowPolicy {
    @MainActor
    static var hasVisibleWindows: Bool {
        SettingsWindowController.shared.isVisible
            || AboutWindowController.shared.isVisible
            || PermissionOnboardingController.shared.isVisible
    }

    @MainActor
    static func refresh() {
        if hasVisibleWindows {
            NSApp.setActivationPolicy(.regular)
        } else if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @MainActor
    static func restoreKeyWindow() {
        if SettingsWindowController.shared.isVisible {
            SettingsWindowController.shared.restoreKey()
        } else if AboutWindowController.shared.isVisible {
            AboutWindowController.shared.restoreKey()
        } else if PermissionOnboardingController.shared.isVisible {
            PermissionOnboardingController.shared.restoreKey()
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let root = SettingsView()
                .environment(AppModel.shared.settings)
                .environment(AppModel.shared.store)
                .environment(AppModel.shared.nowPlaying)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Notch Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 680, height: 440))
            window.minSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .normal
            window.appearance = nil
            window.delegate = self
            window.center()
            self.window = window
        }
        AccessoryWindowPolicy.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func restoreKey() {
        guard isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            AccessoryWindowPolicy.refresh()
        }
    }
}
