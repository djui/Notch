import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let nowPlaying = NowPlayingMonitor()
    let liveActivity = LiveActivityCenter()
    let agents = AgentActivityCenter()
    let shelf = ShelfStore()
    let hosts = NotchHosts()
    let statusItem = StatusItemController()

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let firstLaunch = settings.applyFirstLaunchDefaults()
        nowPlaying.start()
        liveActivity.start()
        agents.start()
        hosts.start()
        statusItem.install(hosts: hosts, settings: settings)
        if firstLaunch {
            PermissionOnboardingController.shared.show()
        }
    }

    func stop() {
        nowPlaying.stop()
        liveActivity.stop()
        agents.stop()
        hosts.stop()
    }
}
