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
        static let hoverHaptics = "hoverHaptics"
        static let agentShowRunning = "agentShowRunning"
        static let agentApprovals = "agentApprovals"
        static let showMeetings = "showMeetings"
        static let showPrivacy = "showPrivacy"
        static let showLevels = "showLevels"
        static let showAudioDevices = "showAudioDevices"
        static let showShelf = "showShelf"
        static let showOnAllDisplays = "showOnAllDisplays"
    }

    var openOnHover: Bool {
        didSet {
            UserDefaults.standard.set(openOnHover, forKey: Keys.openOnHover)
            AppModel.shared.hosts.applyOpenOnHover()
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
            AppModel.shared.hosts.applyOverlayPolicy()
        }
    }

    var layoutStyle: NotchLayoutStyle {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: Keys.layoutStyle)
            AppModel.shared.hosts.applyLayoutStyle()
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

    /// Tap the trackpad when the pointer moves into or out of the notch.
    var hoverHaptics: Bool {
        didSet { UserDefaults.standard.set(hoverHaptics, forKey: Keys.hoverHaptics) }
    }

    /// Show a timer in the collapsed notch while an agent works and nothing else is showing.
    var agentShowRunning: Bool {
        didSet { UserDefaults.standard.set(agentShowRunning, forKey: Keys.agentShowRunning) }
    }

    /// Hold permission prompts for up to 25 seconds so they can be answered from the notch while the agent's app is in the background.
    var agentApprovals: Bool {
        didSet { UserDefaults.standard.set(agentApprovals, forKey: Keys.agentApprovals) }
    }

    /// Count down to the next calendar event with a Join button.
    var showMeetings: Bool {
        didSet {
            UserDefaults.standard.set(showMeetings, forKey: Keys.showMeetings)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    /// Announce when the microphone or camera turns on.
    var showPrivacy: Bool {
        didSet {
            UserDefaults.standard.set(showPrivacy, forKey: Keys.showPrivacy)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    /// Show volume and brightness changes in the notch.
    var showLevels: Bool {
        didSet {
            UserDefaults.standard.set(showLevels, forKey: Keys.showLevels)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    /// Announce Bluetooth headphones connecting, with battery levels.
    var showAudioDevices: Bool {
        didSet {
            UserDefaults.standard.set(showAudioDevices, forKey: Keys.showAudioDevices)
            AppModel.shared.liveActivity.applyPreferences()
        }
    }

    /// Hold files dragged onto the notch.
    var showShelf: Bool {
        didSet { UserDefaults.standard.set(showShelf, forKey: Keys.showShelf) }
    }

    /// A notch on every connected display instead of only the one with a camera housing.
    var showOnAllDisplays: Bool {
        didSet {
            UserDefaults.standard.set(showOnAllDisplays, forKey: Keys.showOnAllDisplays)
            AppModel.shared.hosts.reconcile()
        }
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
        hoverHaptics = Self.bool(Keys.hoverHaptics, default: true)
        agentShowRunning = Self.bool(Keys.agentShowRunning, default: true)
        agentApprovals = Self.bool(Keys.agentApprovals, default: false)
        showMeetings = Self.bool(Keys.showMeetings, default: false)
        showPrivacy = Self.bool(Keys.showPrivacy, default: true)
        showLevels = Self.bool(Keys.showLevels, default: false)
        showAudioDevices = Self.bool(Keys.showAudioDevices, default: true)
        showShelf = Self.bool(Keys.showShelf, default: true)
        showOnAllDisplays = Self.bool(Keys.showOnAllDisplays, default: false)
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
