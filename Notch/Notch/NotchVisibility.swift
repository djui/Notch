import AppKit
import CoreGraphics

/// Hides the notch overlay in fullscreen, games, and while Settings/onboarding should stay usable.
@MainActor
final class NotchVisibility {
    private weak var panel: NotchPanel?
    private let keepVisible: () -> Bool
    private let displayID: () -> CGDirectDisplayID
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var isOrderedOut = false

    init(
        panel: NotchPanel,
        displayID: @escaping () -> CGDirectDisplayID,
        keepVisible: @escaping () -> Bool
    ) {
        self.panel = panel
        self.displayID = displayID
        self.keepVisible = keepVisible
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            workspaceObservers.append(observer)
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    func refresh() {
        guard let panel else { return }
        if keepVisible() {
            show(panel)
            return
        }
        if shouldHide() {
            hide(panel)
        } else {
            show(panel)
        }
    }

    private func shouldHide() -> Bool {
        if AppModel.shared.settings.showInSystemSurfaces {
            return false
        }
        let app = NSWorkspace.shared.frontmostApplication
        if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            if isGame(app) { return true }
            if isFullscreen(app) { return true }
        }
        return false
    }

    private func hide(_ panel: NotchPanel) {
        guard !isOrderedOut else { return }
        isOrderedOut = true
        panel.orderOut(nil)
    }

    private func show(_ panel: NotchPanel) {
        guard isOrderedOut else { return }
        isOrderedOut = false
        panel.orderFrontRegardless()
        panel.applyNotchLevel()
    }

    private func isGame(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, Self.gameLauncherIDs.contains(id) {
            return isFullscreen(app)
        }
        guard let url = app.bundleURL, let bundle = Bundle(url: url) else { return false }
        let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        return category == "public.app-category.games"
    }

    private func isFullscreen(_ app: NSRunningApplication) -> Bool {
        let id = displayID()
        let screen = NSScreen.screens.first(where: { $0.displayID == id })
            ?? NotchGeometry.preferredScreen(preferMouse: false)
        let quartzScreen = Self.quartzFrame(for: screen)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let pid = app.processIdentifier
        return info.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid else { return false }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return false }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let slop: CGFloat = 8
            return rect.width >= quartzScreen.width - slop
                && rect.height >= quartzScreen.height - slop
                && abs(rect.midX - quartzScreen.midX) < 40
        }
    }

    private static let gameLauncherIDs: Set<String> = [
        "com.valvesoftware.steam",
        "com.heroicgameslauncher.hgl",
        "com.epicgames.EpicGamesLauncher",
        "com.epicgames.Fortnite",
    ]

    private static func quartzFrame(for screen: NSScreen) -> CGRect {
        let cocoa = screen.frame
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? cocoa.maxY
        return CGRect(
            x: cocoa.minX,
            y: globalHeight - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        )
    }
}
