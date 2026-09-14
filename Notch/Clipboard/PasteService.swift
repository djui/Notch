import AppKit
import ApplicationServices

enum PasteService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [prompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func paste(_ item: ClipItem, plainText: Bool, into app: NSRunningApplication?) {
        AppModel.shared.monitor.ignoreNextChange = true
        item.write(to: .general, plainText: plainText)

        let delay: Duration
        if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate()
            delay = .milliseconds(80)
        } else {
            delay = .milliseconds(50)
        }

        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard isTrusted else { return }
            postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
