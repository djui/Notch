import AppKit
import CoreGraphics

struct NotchGeometry: Equatable {
    var displayID: CGDirectDisplayID
    var screenFrame: CGRect
    var isArtificial: Bool
    var layoutStyle: NotchLayoutStyle
    var collapsedFrame: CGRect
    var expandedSize: CGSize
    var earRadius: CGFloat

    static let artificialWidth: CGFloat = 185
    static let hoverPeekWidth: CGFloat = 14
    static let hoverPeekHeight: CGFloat = 6
    static let collapsedMenuBarInset: CGFloat = 4
    static let islandMenuBarMargin: CGFloat = 3
    static let islandArtificialWidth: CGFloat = 170
    static let islandSidePadding: CGFloat = 6
    static let expandedIslandCornerRadius: CGFloat = 32
    static let collapsedNotchCornerRadius: CGFloat = 11
    static let expandedNotchCornerRadius: CGFloat = 26

    var collapsedSize: CGSize { collapsedFrame.size }

    func notchCornerRadii(expanded: Bool) -> (ear: CGFloat, bottom: CGFloat) {
        let radius = expanded ? Self.expandedNotchCornerRadius : Self.collapsedNotchCornerRadius
        return (radius, radius)
    }

    func collapsedSize(peeking: Bool) -> CGSize {
        let base = collapsedSize
        guard peeking else { return base }
        let extraHeight = layoutStyle == .island ? 0 : Self.hoverPeekHeight
        return CGSize(
            width: base.width + Self.hoverPeekWidth,
            height: base.height + extraHeight
        )
    }

    var expandedCornerRadius: CGFloat { Self.expandedIslandCornerRadius }

    var expandedWindowFrame: CGRect { windowFrame(for: expandedSize) }

    var collapsedWindowFrame: CGRect { collapsedFrame }

    /// Room for the click-to-open hover grow without moving the window.
    /// Top edge and horizontal center stay on the collapsed notch.
    func collapsedWindowFrame(hoverPeekReserved: Bool) -> CGRect {
        hoverPeekReserved
            ? windowFrame(for: collapsedSize(peeking: true))
            : collapsedFrame
    }

    var expandedPanelFrame: CGRect { expandedWindowFrame }

    func windowFrame(expanded: Bool) -> CGRect {
        expanded ? expandedWindowFrame : collapsedWindowFrame
    }

    func panelFrame(expanded: Bool) -> CGRect {
        expanded ? expandedPanelFrame : collapsedWindowFrame
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

    func visualFrame(in bounds: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Screen-space region that should count as hovering the overlay.
    /// Island uses the full menu-bar strip so the 3pt gaps around the capsule
    /// still open-on-hover (those pixels belong to the system menu bar).
    func hoverScreenFrame(visualSize: CGSize, panelFrame: CGRect, expanded: Bool) -> CGRect {
        if !expanded, layoutStyle == .island {
            let pad: CGFloat = 10
            let top = screenFrame.maxY
            let bottom = collapsedFrame.minY - pad
            return CGRect(
                x: collapsedFrame.minX - pad,
                y: bottom,
                width: collapsedFrame.width + pad * 2,
                height: max(collapsedFrame.height, top - bottom)
            )
        }
        return CGRect(
            x: panelFrame.midX - visualSize.width / 2,
            y: panelFrame.maxY - visualSize.height,
            width: visualSize.width,
            height: visualSize.height
        ).insetBy(dx: -4, dy: -4)
    }

    static func current(style: NotchLayoutStyle, mouseScreenForHotkey: Bool = false) -> NotchGeometry {
        make(for: preferredScreen(preferMouse: mouseScreenForHotkey), style: style)
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

    static func make(for screen: NSScreen, style: NotchLayoutStyle) -> NotchGeometry {
        let expandedWidth = min(760, max(520, screen.frame.width * 0.62))
        let expandedHeight: CGFloat = 300
        let expandedSize = CGSize(width: expandedWidth, height: expandedHeight)

        if let real = hardwareNotchFrame(on: screen) {
            let collapsed = style == .island
                ? islandFrame(covering: real, on: screen)
                : notchFrame(covering: real, on: screen)
            return NotchGeometry(
                displayID: screen.displayID,
                screenFrame: screen.frame,
                isArtificial: false,
                layoutStyle: style,
                collapsedFrame: collapsed,
                expandedSize: expandedSize,
                earRadius: 7
            )
        }

        let collapsed: CGRect
        if style == .island {
            collapsed = islandFrameArtificial(on: screen)
        } else {
            collapsed = notchFrameArtificial(on: screen)
        }
        return NotchGeometry(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            isArtificial: true,
            layoutStyle: style,
            collapsedFrame: collapsed,
            expandedSize: expandedSize,
            earRadius: 6
        )
    }

    private static func collapsedNotchHeight(for screen: NSScreen) -> CGFloat {
        max(20, screen.menuBarHeight - collapsedMenuBarInset)
    }

    private static func notchFrame(covering hardware: CGRect, on screen: NSScreen) -> CGRect {
        let height = collapsedNotchHeight(for: screen)
        return CGRect(
            x: hardware.minX,
            y: screen.frame.maxY - height,
            width: hardware.width,
            height: height
        )
    }

    private static func notchFrameArtificial(on screen: NSScreen) -> CGRect {
        let height = collapsedNotchHeight(for: screen)
        let width = Self.artificialWidth
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Capsule sits inside the menu bar with equal top and bottom gaps.
    private static func islandMetrics(on screen: NSScreen) -> (height: CGFloat, topInset: CGFloat) {
        let bar = max(screen.menuBarHeight, 24)
        let height = max(16, bar - islandMenuBarMargin * 2)
        let topInset = max(islandMenuBarMargin, (bar - height) / 2)
        return (height, topInset)
    }

    private static func islandFrame(covering hardware: CGRect, on screen: NSScreen) -> CGRect {
        let metrics = islandMetrics(on: screen)
        let width = hardware.width + Self.islandSidePadding * 2
        let x = hardware.midX - width / 2
        let y = screen.frame.maxY - metrics.topInset - metrics.height
        return CGRect(x: x, y: y, width: width, height: metrics.height)
    }

    private static func islandFrameArtificial(on screen: NSScreen) -> CGRect {
        let metrics = islandMetrics(on: screen)
        let width = Self.islandArtificialWidth
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - metrics.topInset - metrics.height
        return CGRect(x: x, y: y, width: width, height: metrics.height)
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
