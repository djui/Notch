import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        if let named = NSImage(named: "MenuBarIcon") {
            named.isTemplate = true
            named.size = NSSize(width: 20, height: 12)
            named.accessibilityDescription = "Notch"
            return named
        }
        return generated()
    }

    private static func generated() -> NSImage {
        let size = NSSize(width: 20, height: 12)
        let image = NSImage(size: size, flipped: true) { rect in
            let drawRect = NSRect(x: 0.4, y: 1.0, width: rect.width - 0.8, height: rect.height - 2.0)
            NSColor.black.setFill()
            NSBezierPath(cgPath: NotchPath.cgPath(
                in: drawRect,
                earRadius: 2.2,
                bottomRadius: 2.4
            )).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Notch"
        return image
    }
}
