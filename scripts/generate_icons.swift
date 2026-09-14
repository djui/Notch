#!/usr/bin/env swift
import AppKit

// Generates light, dark, and tinted Mac app icons plus a template menu-bar PDF.
// Run from the repo root: swift scripts/generate_icons.swift

struct Palette {
    var backgroundTop: NSColor
    var backgroundBottom: NSColor
    var notch: NSColor
}

let light = Palette(
    backgroundTop: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.985, alpha: 1),
    backgroundBottom: NSColor(srgbRed: 0.82, green: 0.82, blue: 0.86, alpha: 1),
    notch: .black
)

let dark = Palette(
    backgroundTop: NSColor(srgbRed: 0.32, green: 0.32, blue: 0.34, alpha: 1),
    backgroundBottom: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1),
    notch: .black
)

let tinted = Palette(
    backgroundTop: NSColor(srgbRed: 0.78, green: 0.78, blue: 0.80, alpha: 1),
    backgroundBottom: NSColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1),
    notch: .black
)

func notchCGPath(in rect: CGRect, earRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let ear = min(max(earRadius, 0), rect.width / 4, rect.height / 2)
    let bottom = min(max(bottomRadius, 0), (rect.width - ear * 2) / 2, (rect.height - ear) / 2)
    let left = rect.minX + ear
    let right = rect.maxX - ear
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + ear), control: CGPoint(x: right, y: rect.minY))
    path.addLine(to: CGPoint(x: right, y: rect.maxY - bottom))
    path.addQuadCurve(to: CGPoint(x: right - bottom, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
    path.addLine(to: CGPoint(x: left + bottom, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - bottom), control: CGPoint(x: left, y: rect.maxY))
    path.addLine(to: CGPoint(x: left, y: rect.minY + ear))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat, palette: Palette) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    // Draw in top-down coordinates, matching SwiftUI / NotchPath.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [palette.backgroundTop.cgColor, palette.backgroundBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])

    let compact = size <= 32
    let notchWidth = size * (compact ? 0.72 : 0.62)
    let notchHeight = size * (compact ? 0.36 : 0.22)
    let notchRect = CGRect(
        x: (size - notchWidth) / 2,
        y: 0,
        width: notchWidth,
        height: notchHeight
    )
    let path = notchCGPath(in: notchRect, earRadius: notchHeight * 0.26, bottomRadius: notchHeight * 0.28)
    if !compact {
        ctx.setShadow(
            offset: CGSize(width: 0, height: size * 0.012),
            blur: size * 0.028,
            color: NSColor.black.withAlphaComponent(0.22).cgColor
        )
    }
    ctx.setFillColor(palette.notch.cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

func writePNG(size: Int, palette: Palette, url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap")
    }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Unable to create graphics context")
    }
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    drawIcon(size: CGFloat(size), palette: palette)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode PNG")
    }
    try data.write(to: url)
}

func writeMenuBarPDF(url: URL) {
    var mediaBox = CGRect(x: 0, y: 0, width: 22, height: 12)
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Unable to create PDF")
    }
    ctx.beginPDFPage(nil)
    ctx.setShouldAntialias(true)
    ctx.translateBy(x: 0, y: 12)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(NSColor.black.cgColor)
    let drawRect = CGRect(x: 0.8, y: 1.1, width: 20.4, height: 9.4)
    ctx.addPath(notchCGPath(in: drawRect, earRadius: 2.3, bottomRadius: 2.5))
    ctx.fillPath()
    ctx.endPDFPage()
    ctx.closePDF()
}

func appearance(_ value: String) -> [[String: String]] {
    [["appearance": "luminosity", "value": value]]
}

func imageEntry(filename: String, size: String, scale: String, appearances: [[String: String]]? = nil) -> [String: Any] {
    var entry: [String: Any] = [
        "filename": filename,
        "idiom": "mac",
        "scale": scale,
        "size": size
    ]
    if let appearances {
        entry["appearances"] = appearances
    }
    return entry
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDir = root.appendingPathComponent("Notch/Assets.xcassets/AppIcon.appiconset")
let menuBarDir = root.appendingPathComponent("Notch/Assets.xcassets/MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuBarDir, withIntermediateDirectories: true)

struct IconSlot {
    var point: Int
    var scale: Int
    var name: String
}

let slots: [IconSlot] = [
    .init(point: 16, scale: 1, name: "icon_16x16"),
    .init(point: 16, scale: 2, name: "icon_16x16@2x"),
    .init(point: 32, scale: 1, name: "icon_32x32"),
    .init(point: 32, scale: 2, name: "icon_32x32@2x"),
    .init(point: 128, scale: 1, name: "icon_128x128"),
    .init(point: 128, scale: 2, name: "icon_128x128@2x"),
    .init(point: 256, scale: 1, name: "icon_256x256"),
    .init(point: 256, scale: 2, name: "icon_256x256@2x"),
    .init(point: 512, scale: 1, name: "icon_512x512"),
    .init(point: 512, scale: 2, name: "icon_512x512@2x")
]

var catalog: [[String: Any]] = []
for slot in slots {
    let pixels = slot.point * slot.scale
    let lightName = "\(slot.name).png"
    let darkName = "\(slot.name)-dark.png"
    let tintedName = "\(slot.name)-tinted.png"
    try writePNG(size: pixels, palette: light, url: appIconDir.appendingPathComponent(lightName))
    try writePNG(size: pixels, palette: dark, url: appIconDir.appendingPathComponent(darkName))
    try writePNG(size: pixels, palette: tinted, url: appIconDir.appendingPathComponent(tintedName))
    let sizeKey = "\(slot.point)x\(slot.point)"
    let scaleKey = "\(slot.scale)x"
    catalog.append(imageEntry(filename: lightName, size: sizeKey, scale: scaleKey))
    catalog.append(imageEntry(filename: darkName, size: sizeKey, scale: scaleKey, appearances: appearance("dark")))
    catalog.append(imageEntry(filename: tintedName, size: sizeKey, scale: scaleKey, appearances: appearance("tinted")))
}

let appIconJSON: [String: Any] = [
    "images": catalog,
    "info": ["author": "xcode", "version": 1]
]
let appIconData = try JSONSerialization.data(withJSONObject: appIconJSON, options: [.prettyPrinted, .sortedKeys])
try appIconData.write(to: appIconDir.appendingPathComponent("Contents.json"))

writeMenuBarPDF(url: menuBarDir.appendingPathComponent("MenuBarIcon.pdf"))
let menuJSON: [String: Any] = [
    "images": [[
        "filename": "MenuBarIcon.pdf",
        "idiom": "universal"
    ]],
    "info": ["author": "xcode", "version": 1],
    "properties": [
        "preserves-vector-representation": true,
        "template-rendering-intent": "template"
    ]
]
let menuData = try JSONSerialization.data(withJSONObject: menuJSON, options: [.prettyPrinted, .sortedKeys])
try menuData.write(to: menuBarDir.appendingPathComponent("Contents.json"))

print("Wrote app icons to \(appIconDir.path)")
print("Wrote menu bar icon to \(menuBarDir.path)")
