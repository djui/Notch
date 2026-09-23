import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let nowPlaying = NowPlayingMonitor()
    let liveActivity = LiveActivityCenter()
    let host: NotchHost
    let statusItem = StatusItemController()

    private var started = false

    private init() {
        host = NotchHost()
    }

    func start() {
        guard !started else { return }
        started = true
        let firstLaunch = settings.applyFirstLaunchDefaults()
        nowPlaying.start()
        liveActivity.start()
        host.start()
        statusItem.install(host: host, settings: settings)
        if firstLaunch {
            PermissionOnboardingController.shared.show()
        }
    }

    func stop() {
        nowPlaying.stop()
        liveActivity.stop()
        host.stop()
    }
}
