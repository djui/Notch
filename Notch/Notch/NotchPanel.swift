import AppKit
import QuartzCore
import SwiftUI

final class NotchPanel: NSPanel {
    var allowsKey: Bool = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle
        ]
        sharingType = .none
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isExcludedFromWindowsMenu = true
        applyOverlayPolicy(showInSystemSurfaces: false)
        applyNotchLevel()
        acceptsMouseMovedEvents = true
    }

    func embed(hosting: NSView) {
        let container = NotchContainerView(frame: .zero)
        contentView = container

        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
    }

    func applyOverlayPolicy(showInSystemSurfaces: Bool) {
        if showInSystemSurfaces {
            collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
                .ignoresCycle
            ]
            sharingType = .readOnly
        } else {
            collectionBehavior = [
                .canJoinAllSpaces,
                .transient,
                .ignoresCycle
            ]
            sharingType = .none
        }
        applyNotchLevel()
    }

    func applyNotchLevel() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { allowsKey }

    override func keyDown(with event: NSEvent) {
        // Do not call super — NSResponder beeps for unhandled keys.
    }

    override func keyUp(with event: NSEvent) {}

    override func interpretKeyEvents(_ eventArray: [NSEvent]) {}

    override func doCommand(by selector: Selector) {}

    /// WindowServer otherwise interpolates `setFrame` as a scale from the window center.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0 }

    func setFrameImmediately(_ frame: NSRect, display: Bool = true) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setFrame(frame, display: display)
            CATransaction.commit()
        }
        applyNotchLevel()
    }

    func setAcceptsKeyboard(_ enabled: Bool) {
        allowsKey = enabled
        if enabled {
            styleMask.remove(.nonactivatingPanel)
        } else {
            styleMask.insert(.nonactivatingPanel)
            if isKeyWindow {
                resignKey()
            }
        }
        applyNotchLevel()
    }
}

final class SilentHostingView<Content: View>: NSHostingView<Content> {
    var shouldAcceptHit: ((NSPoint) -> Bool)?

    override var isOpaque: Bool { false }

    override var acceptsFirstResponder: Bool {
        (window as? NotchPanel)?.allowsKey ?? false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let shouldAcceptHit, !shouldAcceptHit(point) {
            return nil
        }
        return super.hitTest(point)
    }

    override func keyDown(with event: NSEvent) {
        // Swallow — default NSResponder implementation plays the system beep.
    }

    override func interpretKeyEvents(_ eventArray: [NSEvent]) {}

    override func doCommand(by selector: Selector) {}
}

final class NotchContainerView: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
