import AppKit
import ApplicationServices
import CoreGraphics

enum PasteService {
    static var isTrusted: Bool {
        if AXIsProcessTrusted() { return true }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: false] as CFDictionary) { return true }
        return CGPreflightPostEventAccess()
    }

    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !isTrusted {
            _ = CGRequestPostEventAccess()
        }
    }

    @MainActor
    static func paste(_ item: ClipItem, plainText: Bool, into app: NSRunningApplication?) {
        AppModel.shared.monitor.ignoreNextChange = true
        item.write(to: .general, plainText: plainText)

        let target = pasteTarget(from: app)
        Task { @MainActor in
            if let target {
                NSApp.yieldActivation(to: target)
                _ = target.activate()
                try? await Task.sleep(for: .milliseconds(200))
            } else {
                try? await Task.sleep(for: .milliseconds(80))
            }
            postCommandV()
        }
    }

    private static func pasteTarget(from app: NSRunningApplication?) -> NSRunningApplication? {
        if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, !app.isTerminated {
            return app
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return nil
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
