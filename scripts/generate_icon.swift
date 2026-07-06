#!/usr/bin/env swift
// Generates the AppIcon iconset for Aranet4 Logger: an Aranet4-style device face showing a
// CO2 reading (with the unit stacked under the number, echoing the menu bar), on a teal
// gradient squircle. Usage: swift scripts/generate_icon.swift <output-iconset-dir>
// Then: iconutil -c icns <output-iconset-dir> -o AppIcon.icns
import AppKit

let designSize: CGFloat = 1024

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

func drawCentered(_ string: String, font: NSFont, color: NSColor, centerY: CGFloat, scale s: CGFloat) {
    let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let size = text.size()
    text.draw(at: NSPoint(x: (designSize * s - size.width) / 2, y: centerY - size.height / 2))
}

/// Draw the full icon into the current graphics context at `s` (pixels per design point).
func draw(scale s: CGFloat) {
    // Background squircle on the standard macOS icon grid (824 pt of the 1024 pt canvas).
    let background = NSBezierPath(
        roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
        xRadius: 186 * s, yRadius: 186 * s
    )
    NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.72, alpha: 1),
        ending: NSColor(calibratedRed: 0.24, green: 0.80, blue: 0.66, alpha: 1)
    )!.draw(in: background, angle: 90)

    // Device body: white rounded square with a soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    let device = NSBezierPath(
        roundedRect: NSRect(x: 240 * s, y: 240 * s, width: 544 * s, height: 544 * s),
        xRadius: 108 * s, yRadius: 108 * s
    )
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    device.fill()
    NSGraphicsContext.restoreGraphicsState()

    // E-ink display.
    let display = NSBezierPath(
        roundedRect: NSRect(x: 306 * s, y: 420 * s, width: 412 * s, height: 296 * s),
        xRadius: 36 * s, yRadius: 36 * s
    )
    NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.89, alpha: 1).setFill()
    display.fill()

    // The reading: number with the unit stacked beneath it.
    drawCentered(
        "412", font: roundedFont(size: 165, weight: .bold).withSize(165 * s),
        color: NSColor(calibratedWhite: 0.13, alpha: 1), centerY: 610 * s, scale: s
    )
    drawCentered(
        "ppm", font: roundedFont(size: 62, weight: .semibold).withSize(62 * s),
        color: NSColor(calibratedWhite: 0.38, alpha: 1), centerY: 472 * s, scale: s
    )

    // Green "good air" status pill under the display.
    let pill = NSBezierPath(
        roundedRect: NSRect(x: 306 * s, y: 306 * s, width: 412 * s, height: 64 * s),
        xRadius: 32 * s, yRadius: 32 * s
    )
    NSColor(calibratedRed: 0.44, green: 0.79, blue: 0.35, alpha: 1).setFill()
    pill.fill()
}

func writePNG(pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(scale: CGFloat(pixels) / designSize)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_icon.swift <output-iconset-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in entries {
    try writePNG(pixels: pixels, to: outDir.appendingPathComponent("\(name).png"))
}
print("Wrote \(entries.count) images to \(outDir.path)")
