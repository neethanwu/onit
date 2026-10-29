import AppKit

/// The "orbit" icon: a ring, a center dot for your Mac, and a bead for a job.
/// Only the bead takes a status color; otherwise the icon is a template and follows the menu bar.
enum MenuBarIcon {
    static let restingAngle = -45.0
    static let lapSeconds = 4.0

    static func image(for state: OverallState, beadAngle: Double) -> NSImage {
        let beadColor: NSColor? = switch state {
        case .failed: .systemRed
        case .headsUp: .systemOrange
        default: nil
        }
        let alpha: CGFloat = state == .empty ? 0.4 : 1

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ink = (beadColor == nil ? NSColor.black : NSColor.labelColor).withAlphaComponent(alpha)
            let center = NSPoint(x: 9, y: 9)

            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
            ring.lineWidth = 1.5
            ink.setStroke()
            ring.stroke()

            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8)).fill()

            let radians = beadAngle * .pi / 180
            let bead = NSPoint(x: center.x + 6 * cos(radians), y: center.y + 6 * sin(radians))
            (beadColor ?? ink).setFill()
            NSBezierPath(ovalIn: NSRect(x: bead.x - 2.5, y: bead.y - 2.5, width: 5, height: 5)).fill()
            return true
        }
        image.isTemplate = beadColor == nil
        image.accessibilityDescription = accessibilityLabel(for: state)
        return image
    }

    private static func accessibilityLabel(for state: OverallState) -> String {
        switch state {
        case .empty: "onit: nothing scheduled"
        case .ok: "onit: all jobs OK"
        case .running: "onit: a job is running"
        case .headsUp: "onit: a job needs a look"
        case .failed: "onit: a job failed"
        }
    }
}
