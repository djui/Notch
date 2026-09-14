import Foundation
import ServiceManagement
import SwiftUI

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let didCompleteFirstLaunch = "didCompleteFirstLaunch"
        static let isPaused = "isPaused"
        static let historyLimit = "historyLimit"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let openOnHover = "openOnHover"
        static let showNowPlaying = "showNowPlaying"
        static let showStatusItem = "showStatusItem"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let plainHotkeyKeyCode = "plainHotkeyKeyCode"
        static let plainHotkeyModifiers = "plainHotkeyModifiers"
    }

    var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Keys.isPaused) }
    }

    var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: Keys.historyLimit) }
    }

    var ignoredBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(ignoredBundleIDs), forKey: Keys.ignoredBundleIDs)
        }
    }

    var openOnHover: Bool {
        didSet { UserDefaults.standard.set(openOnHover, forKey: Keys.openOnHover) }
    }

    var showNowPlaying: Bool {
        didSet { UserDefaults.standard.set(showNowPlaying, forKey: Keys.showNowPlaying) }
    }

    var showStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showStatusItem, forKey: Keys.showStatusItem)
            AppModel.shared.statusItem.applyVisibility()
        }
    }

    var openShortcut: KeyboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(openShortcut.keyCode), forKey: Keys.hotkeyKeyCode)
            UserDefaults.standard.set(Int(openShortcut.carbonModifiers), forKey: Keys.hotkeyModifiers)
            AppModel.shared.registerHotkeys()
        }
    }

    var plainPasteShortcut: KeyboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(plainPasteShortcut.keyCode), forKey: Keys.plainHotkeyKeyCode)
            UserDefaults.standard.set(Int(plainPasteShortcut.carbonModifiers), forKey: Keys.plainHotkeyModifiers)
            AppModel.shared.registerHotkeys()
        }
    }

    var launchAtLogin: Bool

    var loginItemBlocked: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    init() {
        isPaused = UserDefaults.standard.bool(forKey: Keys.isPaused)
        let storedLimit = UserDefaults.standard.integer(forKey: Keys.historyLimit)
        historyLimit = storedLimit > 0 ? storedLimit : 500
        let ignored = UserDefaults.standard.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        ignoredBundleIDs = Set(ignored)
        if UserDefaults.standard.object(forKey: Keys.openOnHover) == nil {
            openOnHover = true
        } else {
            openOnHover = UserDefaults.standard.bool(forKey: Keys.openOnHover)
        }
        if UserDefaults.standard.object(forKey: Keys.showNowPlaying) == nil {
            showNowPlaying = true
        } else {
            showNowPlaying = UserDefaults.standard.bool(forKey: Keys.showNowPlaying)
        }
        if UserDefaults.standard.object(forKey: Keys.showStatusItem) == nil {
            showStatusItem = true
        } else {
            showStatusItem = UserDefaults.standard.bool(forKey: Keys.showStatusItem)
        }
        openShortcut = Self.loadShortcut(
            keyCodeKey: Keys.hotkeyKeyCode,
            modifiersKey: Keys.hotkeyModifiers,
            fallback: .defaultOpen,
            requireGlobal: true
        )
        plainPasteShortcut = Self.loadShortcut(
            keyCodeKey: Keys.plainHotkeyKeyCode,
            modifiersKey: Keys.plainHotkeyModifiers,
            fallback: .defaultPlainPaste,
            requireGlobal: false
        )
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func loadShortcut(
        keyCodeKey: String,
        modifiersKey: String,
        fallback: KeyboardShortcut,
        requireGlobal: Bool
    ) -> KeyboardShortcut {
        guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else { return fallback }
        let stored = KeyboardShortcut(
            keyCode: UInt32(UserDefaults.standard.integer(forKey: keyCodeKey)),
            carbonModifiers: UInt32(UserDefaults.standard.integer(forKey: modifiersKey))
        )
        if requireGlobal {
            return stored.isValidGlobal ? stored : fallback
        }
        return stored.isValidLocal ? stored : fallback
    }

    func applyFirstLaunchDefaults() {
        if !UserDefaults.standard.bool(forKey: Keys.didCompleteFirstLaunch) {
            UserDefaults.standard.set(true, forKey: Keys.didCompleteFirstLaunch)
            setLaunchAtLogin(true)
        } else {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    launchAtLogin = true
                    return
                }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Notch: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
