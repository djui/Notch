import AppKit
import ApplicationServices
import CoreServices

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
            if app.isHidden {
                _ = app.unhide()
            }
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
        reopenAndActivate(app)

        guard !item.isWebSource else { return }
        try? await Task.sleep(for: .milliseconds(150))
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

    /// Dock-click equivalent: unhide, reopen closed windows, then activate.
    private static func reopenAndActivate(_ app: NSRunningApplication) {
        if app.isHidden {
            _ = app.unhide()
        }
        sendReopenEvent(to: app)
        _ = app.activate(options: [.activateAllWindows])
    }

    private static func sendReopenEvent(to app: NSRunningApplication) {
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply, .neverInteract], timeout: 1)
    }

    private static func raiseMatchingWindow(for item: NowPlayingItem, app: NSRunningApplication) {
        guard PermissionStatus.isAccessibilityTrusted else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty
        else { return }

        let hint = item.displayTitle.lowercased()
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
            if !hint.isEmpty, lower.contains(hint) { score += 10 }
            if !artist.isEmpty, lower.contains(artist) { score += 3 }
            if score > bestScore {
                bestScore = score
                best = window
            }
        }
        raise(bestScore >= 10 ? best : windows.first)
    }

    private static func raise(_ window: AXUIElement?) {
        guard let window else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
