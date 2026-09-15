import AppKit
import ApplicationServices

@MainActor
enum NowPlayingSource {
    static func reveal(_ item: NowPlayingItem?) {
        guard let item else { return }
        Task { @MainActor in
            await revealSource(item)
        }
    }

    private static func revealSource(_ item: NowPlayingItem) async {
        let app = runningApp(for: item)
        if let app {
            NSApp.yieldActivation(to: app)
        }

        if item.isWebSource, let bundleID = item.bundleIdentifier, !bundleID.isEmpty {
            let activated = await Task.detached(priority: .userInitiated) {
                BrowserMediaTabs.activateMatchingTab(bundleID: bundleID, item: item)
            }.value
            if activated { return }
        }

        guard let app else {
            launch(item)
            return
        }
        _ = app.activate()

        guard !item.isWebSource else { return }
        try? await Task.sleep(for: .milliseconds(100))
        raiseMatchingWindow(for: item, app: app)
    }

    private static func runningApp(for item: NowPlayingItem) -> NSRunningApplication? {
        guard let bundleID = item.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    private static func launch(_ item: NowPlayingItem) {
        guard let bundleID = item.bundleIdentifier, !bundleID.isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func raiseMatchingWindow(for item: NowPlayingItem, app: NSRunningApplication) {
        guard PasteService.isTrusted else { return }
        let hint = item.displayTitle.lowercased()
        guard !hint.isEmpty else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return }

        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var best: AXUIElement?
        var bestScore = 0
        for window in windows {
            var titleRef: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String
            else { continue }
            let lower = title.lowercased()
            var score = 0
            if lower.contains(hint) { score += 10 }
            if !artist.isEmpty, lower.contains(artist) { score += 3 }
            if score > bestScore {
                bestScore = score
                best = window
            }
        }
        guard let best, bestScore >= 10 else { return }
        AXUIElementPerformAction(best, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(best, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(best, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
