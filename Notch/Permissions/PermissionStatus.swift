import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined
    case unavailable
}

enum AutomationTarget: String, CaseIterable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        case .safari: "Safari"
        case .chrome: "Chrome"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }
}

enum PermissionStatus {
    static var isAccessibilityTrusted: Bool {
        if AXIsProcessTrusted() { return true }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: false] as CFDictionary) { return true }
        return CGPreflightPostEventAccess()
    }

    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !isAccessibilityTrusted {
            _ = CGRequestPostEventAccess()
        }
    }

    static func openAccessibilitySettings() {
        openSystemSettings(privacyAnchor: "Privacy_Accessibility")
    }

    static func openAutomationSettings() {
        openSystemSettings(privacyAnchor: "Privacy_Automation")
    }

    static func openFullDiskAccessSettings() {
        openSystemSettings(privacyAnchor: "Privacy_AllFiles")
    }

    static func automationState(_ target: AutomationTarget, prompt: Bool) -> PermissionState {
        guard target.isInstalled else { return .unavailable }
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.rawValue)
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor.aeDesc,
            typeWildCard,
            typeWildCard,
            prompt
        )
        switch Int(status) {
        case 0:
            rememberGranted(target)
            return .granted
        case Int(errAEEventNotPermitted):
            forgetGranted(target)
            return .denied
        default:
            if wasGranted(target) {
                return .granted
            }
            return .notDetermined
        }
    }

    static func requestAutomation(_ target: AutomationTarget) {
        _ = automationState(target, prompt: true)
    }

    private static let grantedDefaultsKey = "automationGrantedBundleIDs"

    private static func grantedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: grantedDefaultsKey) ?? [])
    }

    private static func rememberGranted(_ target: AutomationTarget) {
        var ids = grantedIDs()
        ids.insert(target.rawValue)
        UserDefaults.standard.set(Array(ids), forKey: grantedDefaultsKey)
    }

    private static func forgetGranted(_ target: AutomationTarget) {
        var ids = grantedIDs()
        ids.remove(target.rawValue)
        UserDefaults.standard.set(Array(ids), forKey: grantedDefaultsKey)
    }

    private static func wasGranted(_ target: AutomationTarget) -> Bool {
        grantedIDs().contains(target.rawValue)
    }

    private static func openSystemSettings(privacyAnchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(privacyAnchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)",
        ]
        for string in candidates {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

@Observable
@MainActor
final class PermissionCenter {
    var accessibilityTrusted = PermissionStatus.isAccessibilityTrusted
    var focusDatabaseReadable = FocusMonitor.canReadAssertions
    var automation: [AutomationTarget: PermissionState] = [:]

    func refresh() {
        refreshAccessibility()
        focusDatabaseReadable = FocusMonitor.canReadAssertions
        var next: [AutomationTarget: PermissionState] = [:]
        for target in AutomationTarget.allCases {
            next[target] = PermissionStatus.automationState(target, prompt: false)
        }
        automation = next
    }

    func refreshAccessibility() {
        accessibilityTrusted = PermissionStatus.isAccessibilityTrusted
    }

    func requestAccessibility() {
        PermissionStatus.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    func requestAutomation(_ target: AutomationTarget) {
        PermissionStatus.requestAutomation(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }
}
