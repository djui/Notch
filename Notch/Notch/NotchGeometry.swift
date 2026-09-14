import AppKit
import CoreGraphics

struct NotchGeometry: Equatable {
    var displayID: CGDirectDisplayID
    var screenFrame: CGRect
    var isArtificial: Bool
    var collapsedFrame: CGRect
    var expandedSize: CGSize
    var earRadius: CGFloat

    static let artificialWidth: CGFloat = 185
    static let artificialHeight: CGFloat = 32

    var collapsedSize: CGSize { collapsedFrame.size }

    var expandedWindowFrame: CGRect { windowFrame(for: expandedSize) }

    var collapsedWindowFrame: CGRect { collapsedFrame }

    func windowFrame(expanded: Bool) -> CGRect {
        expanded ? expandedWindowFrame : collapsedWindowFrame
    }

    /// Size grows from the collapsed notch: top edge and horizontal center stay fixed.
    func windowFrame(for size: CGSize) -> CGRect {
        CGRect(
            x: collapsedFrame.midX - size.width / 2,
            y: collapsedFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func current(mouseScreenForHotkey: Bool = false) -> NotchGeometry {
        make(for: preferredScreen(preferMouse: mouseScreenForHotkey))
    }

    static func preferredScreen(preferMouse: Bool) -> NSScreen {
        if !preferMouse, let notched = NSScreen.screens.first(where: { $0.hasHardwareNotch }) {
            return notched
        }
        if preferMouse, let underMouse = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) {
            return underMouse
        }
        if let builtIn = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    static func make(for screen: NSScreen) -> NotchGeometry {
        let expandedWidth = min(760, max(520, screen.frame.width * 0.62))
        let expandedHeight: CGFloat = 300
        let expandedSize = CGSize(width: expandedWidth, height: expandedHeight)

        if let real = hardwareNotchFrame(on: screen) {
            return NotchGeometry(
                displayID: screen.displayID,
                screenFrame: screen.frame,
                isArtificial: false,
                collapsedFrame: real,
                expandedSize: expandedSize,
                earRadius: 7
            )
        }

        let height = max(Self.artificialHeight, screen.menuBarHeight)
        let width = Self.artificialWidth
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NotchGeometry(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            isArtificial: true,
            collapsedFrame: CGRect(x: x, y: y, width: width, height: height),
            expandedSize: expandedSize,
            earRadius: 6
        )
    }

    private static func hardwareNotchFrame(on screen: NSScreen) -> CGRect? {
        guard screen.hasHardwareNotch else { return nil }
        let height = screen.safeAreaInsets.top
        guard height > 0 else { return nil }

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let x = left.maxX
            let width = max(120, right.minX - left.maxX)
            let y = screen.frame.maxY - height
            return CGRect(x: x, y: y, width: width, height: height)
        }

        let width = Self.artificialWidth
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    var hasHardwareNotch: Bool {
        safeAreaInsets.top > 0
    }

    var menuBarHeight: CGFloat {
        max(0, frame.maxY - visibleFrame.maxY)
    }
}
