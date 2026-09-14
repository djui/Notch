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

        let paste: () -> Void = {
            guard isTrusted else { return }
            postCommandV()
        }

        if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: paste)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: paste)
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
