import AppKit
import ApplicationServices

/// Brings another app's window forward through Accessibility, picked by its title.
@MainActor
enum WindowRaiser {
    /// Raises the window whose lowercased title scores highest. Below `minimumScore`, raises the
    /// first window when `fallbackToFirst` is set and leaves the order alone otherwise.
    static func raiseWindow(
        of app: NSRunningApplication,
        minimumScore: Int,
        fallbackToFirst: Bool,
        score: (String) -> Int
    ) {
        guard PermissionStatus.isAccessibilityTrusted else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, kCFBooleanFalse)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty
        else { return }

        var best: AXUIElement?
        var bestScore = 0
        for window in windows {
            var titleRef: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String
            else { continue }
            let value = score(title.lowercased())
            if value > bestScore {
                bestScore = value
                best = window
            }
        }
        if bestScore >= minimumScore {
            raise(best)
        } else if fallbackToFirst {
            raise(windows.first)
        }
    }

    private static func raise(_ window: AXUIElement?) {
        guard let window else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
