// Draws the onit app icon and builds SupportFiles/AppIcon.icns.
// Run from the repo root: swift SupportFiles/generate-icon.swift
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in context: CGContext) {
    // macOS icon grid: an 824pt rounded square centred on the 1024pt canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Night sky: indigo at the top settling into near-black.
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.17, green: 0.18, blue: 0.30, alpha: 1).cgColor,
        NSColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The orbit from the first icon, now quiet in the background.
    let center = CGPoint(x: 512, y: 500)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.setLineWidth(12)
    context.strokeEllipse(in: CGRect(x: center.x - 300, y: center.y - 300, width: 600, height: 600))

    // A small blue task going round, at the top right of the orbit.
    let angle = CGFloat.pi / 4
    let task = CGPoint(x: center.x + 300 * cos(angle), y: center.y + 300 * sin(angle))
    context.setFillColor(NSColor(red: 0.30, green: 0.64, blue: 1, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: task.x - 34, y: task.y - 34, width: 68, height: 68))

    // Bead, in the middle, keeping an eye on it.
    let bead = CGRect(x: center.x - 205, y: center.y - 205, width: 410, height: 410)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    context.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
    context.fillEllipse(in: bead)
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: bead)
    context.clip()
    let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(white: 1, alpha: 1).cgColor,
        NSColor(red: 0.84, green: 0.85, blue: 0.90, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(shade, startCenter: CGPoint(x: center.x - 60, y: center.y + 80), startRadius: 0,
                               endCenter: CGPoint(x: center.x - 20, y: center.y + 20), endRadius: 300, options: [.drawsAfterEndLocation])
    context.restoreGState()

    // Eyes looking up toward the task.
    context.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
    for side: CGFloat in [-1, 1] {
        let eye = CGPoint(x: center.x + side * 72 + 14, y: center.y + 36)
        context.fillEllipse(in: CGRect(x: eye.x - 31, y: eye.y - 34, width: 62, height: 68))
    }

    context.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "SupportFiles/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "SupportFiles/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote SupportFiles/AppIcon.icns" : "iconutil failed")
