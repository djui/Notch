import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let store = ClipboardStore()
    let nowPlaying = NowPlayingMonitor()
    let liveActivity = LiveActivityCenter()
    let host: NotchHost
    let monitor: ClipboardMonitor
    let openHotkey = GlobalHotkey(id: 1)
    let plainPasteHotkey = GlobalHotkey(id: 2)
    let statusItem = StatusItemController()

    private var started = false

    private init() {
        host = NotchHost()
        monitor = ClipboardMonitor(store: store, settings: settings)
        host.install(module: ClipboardModule(store: store, host: host, settings: settings))
    }

    func start() {
        guard !started else { return }
        started = true
        let firstLaunch = settings.applyFirstLaunchDefaults()
        store.load()
        if settings.clipboardEnabled {
            monitor.start()
        }
        nowPlaying.start()
        liveActivity.start()
        host.start()
        registerHotkeys()
        statusItem.install(host: host, settings: settings)
        if firstLaunch {
            PermissionOnboardingController.shared.show()
        }
    }

    func applyClipboardEnabled() {
        guard started else { return }
        if settings.clipboardEnabled {
            monitor.start()
        } else {
            monitor.stop()
            store.searchQuery = ""
        }
        registerHotkeys()
        statusItem.refreshMenu()
    }

    func registerHotkeys() {
        let open = settings.openShortcut
        openHotkey.register(keyCode: open.keyCode, modifiers: open.carbonModifiers) { [weak self] in
            self?.host.toggleFromHotkey()
        }

        let plain = settings.plainPasteShortcut
        if settings.clipboardEnabled, plain.isValidGlobal {
            plainPasteHotkey.register(keyCode: plain.keyCode, modifiers: plain.carbonModifiers) { [weak self] in
                self?.pasteSelectedAsPlainText()
            }
        } else {
            plainPasteHotkey.unregister()
        }
        statusItem.refreshMenu()
    }

    func pasteSelectedAsPlainText() {
        guard settings.clipboardEnabled else { return }
        guard let item = store.selectedItem ?? store.filteredItems.first else { return }
        if host.isExpanded {
            host.pasteItem(item, plainText: true)
        } else {
            let app = NSWorkspace.shared.frontmostApplication
            PasteService.paste(item, plainText: true, into: app)
        }
    }

    func stop() {
        openHotkey.unregister()
        plainPasteHotkey.unregister()
        nowPlaying.stop()
        liveActivity.stop()
        monitor.stop()
        host.stop()
    }
}
