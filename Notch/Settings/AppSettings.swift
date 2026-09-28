import Foundation
import ServiceManagement

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let didCompleteFirstLaunch = "didCompleteFirstLaunch"
        static let openOnHover = "openOnHover"
        static let showNowPlaying = "showNowPlaying"
        static let showBattery = "showBattery"
        static let showFocus = "showFocus"
        static let showStatusItem = "showStatusItem"
        static let showInSystemSurfaces = "showInSystemSurfaces"
        static let layoutStyle = "layoutStyle"
        static let showAgents = "showAgents"
        static let agentAttention = "agentAttention"
        static let agentFinished = "agentFinished"
        static let agentErrors = "agentErrors"
        static let agentOther = "agentOther"
        static let agentSounds = "agentSounds"
        static let agentQuietWhenFrontmost = "agentQuietWhenFrontmost"
    }

    var openOnHover: Bool {
        didSet {
            UserDefaults.standard.set(openOnHover, forKey: Keys.openOnHover)
            AppModel.shared.host.applyOpenOnHover()
        }
    }

    var showNowPlaying: Bool {
        didSet { UserDefaults.standard.set(showNowPlaying, forKey: Keys.showNowPlaying) }
    }

    var showBattery: Bool {
        didSet {
            UserDefaults.standard.set(showBattery, forKey: Keys.showBattery)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    var showFocus: Bool {
        didSet {
            UserDefaults.standard.set(showFocus, forKey: Keys.showFocus)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    var showStatusItem: Bool {
        didSet {
            UserDefaults.standard.set(showStatusItem, forKey: Keys.showStatusItem)
            AppModel.shared.statusItem.applyVisibility()
        }
    }

    var showInSystemSurfaces: Bool {
        didSet {
            UserDefaults.standard.set(showInSystemSurfaces, forKey: Keys.showInSystemSurfaces)
            AppModel.shared.host.applyOverlayPolicy()
        }
    }

    var layoutStyle: NotchLayoutStyle {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: Keys.layoutStyle)
            AppModel.shared.host.applyLayoutStyle()
        }
    }

    var showAgents: Bool {
        didSet {
            UserDefaults.standard.set(showAgents, forKey: Keys.showAgents)
            AppModel.shared.agents.applyPreferences()
        }
    }

    var agentAttention: Bool {
        didSet { UserDefaults.standard.set(agentAttention, forKey: Keys.agentAttention) }
    }

    var agentFinished: Bool {
        didSet { UserDefaults.standard.set(agentFinished, forKey: Keys.agentFinished) }
    }

    var agentErrors: Bool {
        didSet { UserDefaults.standard.set(agentErrors, forKey: Keys.agentErrors) }
    }

    /// Session start and end, compaction, and subagents.
    var agentOther: Bool {
        didSet { UserDefaults.standard.set(agentOther, forKey: Keys.agentOther) }
    }

    var agentSounds: Bool {
        didSet { UserDefaults.standard.set(agentSounds, forKey: Keys.agentSounds) }
    }

    /// Skip finished and other banners while the agent's terminal or IDE is frontmost.
    var agentQuietWhenFrontmost: Bool {
        didSet { UserDefaults.standard.set(agentQuietWhenFrontmost, forKey: Keys.agentQuietWhenFrontmost) }
    }

    var launchAtLogin: Bool

    var loginItemBlocked: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    init() {
        openOnHover = Self.bool(Keys.openOnHover, default: true)
        showNowPlaying = Self.bool(Keys.showNowPlaying, default: true)
        showBattery = Self.bool(Keys.showBattery, default: true)
        showFocus = Self.bool(Keys.showFocus, default: true)
        showStatusItem = Self.bool(Keys.showStatusItem, default: true)
        showInSystemSurfaces = Self.bool(Keys.showInSystemSurfaces, default: false)
        showAgents = Self.bool(Keys.showAgents, default: true)
        agentAttention = Self.bool(Keys.agentAttention, default: true)
        agentFinished = Self.bool(Keys.agentFinished, default: true)
        agentErrors = Self.bool(Keys.agentErrors, default: true)
        agentOther = Self.bool(Keys.agentOther, default: false)
        agentSounds = Self.bool(Keys.agentSounds, default: true)
        agentQuietWhenFrontmost = Self.bool(Keys.agentQuietWhenFrontmost, default: true)
        if let stored = UserDefaults.standard.string(forKey: Keys.layoutStyle),
           let style = NotchLayoutStyle(rawValue: stored) {
            layoutStyle = style
        } else {
            layoutStyle = .notch
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }

    @discardableResult
    func applyFirstLaunchDefaults() -> Bool {
        if !UserDefaults.standard.bool(forKey: Keys.didCompleteFirstLaunch) {
            UserDefaults.standard.set(true, forKey: Keys.didCompleteFirstLaunch)
            setLaunchAtLogin(true)
            return true
        } else {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            return false
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

enum NotchLayoutStyle: String, CaseIterable, Identifiable, Hashable {
    case notch
    case island

    var id: Self { self }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .island: "Dynamic Island"
        }
    }
}
