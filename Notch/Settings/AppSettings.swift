import Foundation
import ServiceManagement

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let didCompleteFirstLaunch = "didCompleteFirstLaunch"
        static let openOnHover = "openOnHover"
        static let showNowPlaying = "showNowPlaying"
        static let showStatusItem = "showStatusItem"
        static let showInSystemSurfaces = "showInSystemSurfaces"
        static let layoutStyle = "layoutStyle"
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

    var launchAtLogin: Bool

    var loginItemBlocked: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    init() {
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
        showInSystemSurfaces = UserDefaults.standard.bool(forKey: Keys.showInSystemSurfaces)
        if let stored = UserDefaults.standard.string(forKey: Keys.layoutStyle),
           let style = NotchLayoutStyle(rawValue: stored) {
            layoutStyle = style
        } else {
            layoutStyle = .notch
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
