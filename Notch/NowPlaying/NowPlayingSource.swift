import AppKit
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
        let hint = item.displayTitle.lowercased()
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        WindowRaiser.raiseWindow(of: app, minimumScore: 10, fallbackToFirst: true) { title in
            var score = 0
            if !hint.isEmpty, title.contains(hint) { score += 10 }
            if !artist.isEmpty, title.contains(artist) { score += 3 }
            return score
        }
    }
}
