import AppKit

/// One notch on the preferred display, or one on every display.
@MainActor
final class NotchHosts {
    private(set) var hosts: [NotchHost] = []
    private var started = false
    private var screenObserver: NSObjectProtocol?

    func start() {
        guard !started else { return }
        started = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
        reconcile()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        hosts.forEach { $0.stop() }
        hosts.removeAll()
        started = false
    }

    /// Adds and removes hosts to match the setting and the connected displays.
    func reconcile() {
        guard started else { return }
        let wanted: [CGDirectDisplayID?] = AppModel.shared.settings.showOnAllDisplays
            ? NSScreen.screens.map(\.displayID)
            : [nil]
        let kept = hosts.filter { wanted.contains($0.pinnedDisplayID) }
        for host in hosts where !kept.contains(where: { $0 === host }) {
            host.stop()
        }
        hosts = wanted.map { id in
            if let existing = kept.first(where: { $0.pinnedDisplayID == id }) {
                return existing
            }
            let host = NotchHost(displayID: id)
            host.start()
            return host
        }
    }

    /// The notch on the display under the pointer, else the first one.
    private var hostUnderMouse: NotchHost? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        return hosts.first(where: { $0.pinnedDisplayID != nil && $0.pinnedDisplayID == screen?.displayID })
            ?? hosts.first
    }

    func toggleFromHotkey() {
        hostUnderMouse?.toggleFromHotkey()
    }

    func openSettings() {
        hostUnderMouse?.openSettings()
    }

    func openAbout() {
        hostUnderMouse?.openAbout()
    }

    func stepAside() {
        hosts.forEach { $0.stepAside() }
    }

    func visibilityRefresh() {
        hosts.forEach { $0.visibilityRefresh() }
    }

    func applyOverlayPolicy() {
        hosts.forEach { $0.applyOverlayPolicy() }
    }

    func applyLayoutStyle() {
        hosts.forEach { $0.applyLayoutStyle() }
    }

    func applyOpenOnHover() {
        hosts.forEach { $0.applyOpenOnHover() }
    }
}
