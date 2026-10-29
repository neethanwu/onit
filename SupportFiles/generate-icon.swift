// Draws the onit app icon and builds SupportFiles/AppIcon.icns and assets/icon.png.
// Run from the repo root: swift SupportFiles/generate-icon.swift
import AppKit

let canvas: CGFloat = 1024

/// Bead on the run: the white Bead, eyes on where it's going, with blue speed lines behind it.
func drawIcon(in context: CGContext) {
    // macOS icon grid: an 824pt rounded square centred on the 1024pt canvas.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.addPath(tile)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    // A hairline edge so the black tile still reads on a dark Dock.
    context.addPath(tile)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(3)
    context.strokePath()

    let blue = NSColor(red: 0.30, green: 0.64, blue: 1, alpha: 1).cgColor
    context.setStrokeColor(blue)
    context.setLineWidth(26)
    context.setLineCap(.round)
    for (dy, inset) in [(80.0, 40.0), (0.0, 0.0), (-80.0, 40.0)] as [(CGFloat, CGFloat)] {
        context.move(to: CGPoint(x: 210 + inset, y: 500 + dy))
        context.addLine(to: CGPoint(x: 320, y: 500 + dy))
        context.strokePath()
    }

    let center = CGPoint(x: 560, y: 500)
    let radius: CGFloat = 200
    context.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

    context.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
    let eye = radius * 0.17
    for side: CGFloat in [-1, 1] {
        let point = CGPoint(x: center.x + side * radius * 0.32 + radius * 0.09, y: center.y + radius * 0.05)
        context.fillEllipse(in: CGRect(x: point.x - eye, y: point.y - eye, width: eye * 2, height: eye * 2))
    }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: graphics.cgContext)
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

try FileManager.default.createDirectory(at: URL(fileURLWithPath: "assets"), withIntermediateDirectories: true)
try render(size: 256).write(to: URL(fileURLWithPath: "assets/icon.png"))
print(iconutil.terminationStatus == 0 ? "Wrote SupportFiles/AppIcon.icns and assets/icon.png" : "iconutil failed")
