import AppKit
import Observation
import SwiftUI

/// Where Bead's eyes point and how it sits, for one frame of the menu bar icon.
struct BeadPose: Equatable {
    var look = CGVector.zero
    var blink = false
    var peek = false
    var x: CGFloat = 0
}

/// Bead in the menu bar: the same character as in the notch, drawn small enough for the bar.
/// Calm states are template images so they follow the bar's light or dark appearance;
/// running, heads-up and failed carry their status color.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)
    private static let diameter: CGFloat = 13

    static func image(for mood: BeadMood, pose: BeadPose) -> NSImage {
        let colored: (body: NSColor, eyes: NSColor)? = switch mood {
        case .onIt: (NSColor(BeadMood.onIt.body), NSColor(BeadMood.onIt.eyes))
        case .headsUp: (NSColor(BeadMood.headsUp.body), NSColor(BeadMood.headsUp.eyes))
        case .failed: (NSColor(BeadMood.failed.body), NSColor(BeadMood.failed.eyes))
        case .dozing, .nothing: nil
        }

        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: size.width / 2 + pose.x, y: size.height / 2 + 0.5)
            let body = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)

            if mood == .nothing {
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(1.3)
                context.setLineDash(phase: 0, lengths: [1.6, 1.6])
                context.strokeEllipse(in: body.insetBy(dx: 0.65, dy: 0.65))
                context.setLineDash(phase: 0, lengths: [])
            } else {
                context.setFillColor((colored?.body ?? .black).cgColor)
                context.fillEllipse(in: body)
            }

            // On a template image the eyes are cut out of the body; on a colored one they're drawn dark.
            if colored == nil, mood != .nothing { context.setBlendMode(.clear) }
            let eyeColor = colored?.eyes ?? .black
            context.setFillColor(eyeColor.cgColor)
            context.setStrokeColor(eyeColor.cgColor)

            let eyeGap: CGFloat = 4.2
            let eyeSize: CGFloat = 2.3
            let eyeY = center.y - 0.6 + pose.look.dy * 1.1
            for (index, side) in [-1.0, 1.0].enumerated() {
                let eyeX = center.x + side * eyeGap / 2 + pose.look.dx * 1.3
                let closed = mood == .dozing && !(pose.peek && index == 1)
                if closed {
                    context.setLineWidth(1.2)
                    context.setLineCap(.round)
                    context.move(to: CGPoint(x: eyeX - 1.3, y: eyeY))
                    context.addQuadCurve(to: CGPoint(x: eyeX + 1.3, y: eyeY), control: CGPoint(x: eyeX, y: eyeY + 1.4))
                    context.strokePath()
                } else {
                    let height = pose.blink ? 0.5 : eyeSize
                    context.fillEllipse(in: CGRect(x: eyeX - eyeSize / 2, y: eyeY - height / 2, width: eyeSize, height: height))
                }
            }
            return true
        }
        image.isTemplate = colored == nil
        image.accessibilityDescription = accessibilityLabel(for: mood)
        return image
    }

    private static func accessibilityLabel(for mood: BeadMood) -> String {
        switch mood {
        case .nothing: "onit: nothing scheduled"
        case .dozing: "onit: all tasks OK"
        case .onIt: "onit: a task is running"
        case .headsUp: "onit: a task needs a look"
        case .failed: "onit: a task failed"
        }
    }
}

/// Drives the menu bar Bead with the same habits as the notch one, as a few discrete poses
/// a second rather than a continuous animation, so it costs next to nothing.
@MainActor
@Observable
final class MenuBarBead {
    private(set) var pose = BeadPose()
    private(set) var mood: BeadMood = .nothing
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?

    /// Follows the store's overall state for as long as the app runs.
    func follow(_ store: JobStore) {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                self?.update(for: BeadMood(store.overallState))
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = store.overallState
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func update(for mood: BeadMood) {
        guard mood != self.mood || task == nil else { return }
        self.mood = mood
        task?.cancel()
        pose = BeadPose()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        task = Task { [weak self] in await self?.live(mood) }
    }

    private func live(_ mood: BeadMood) async {
        await withTaskGroup(of: Void.self) { group in
            switch mood {
            case .dozing:
                group.addTask { await self.peekLoop() }
            case .onIt:
                group.addTask { await self.runLoop() }
                group.addTask { await self.blinkLoop() }
            case .headsUp, .failed, .nothing:
                group.addTask { await self.blinkLoop() }
                group.addTask { await self.glanceLoop(mood) }
            }
        }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.4...5.2)))
            pose.blink = true
            try? await Task.sleep(for: .seconds(0.12))
            pose.blink = false
        }
    }

    private func peekLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 7...11)))
            pose.peek = true
            try? await Task.sleep(for: .seconds(0.8))
            pose.peek = false
        }
    }

    private func glanceLoop(_ mood: BeadMood) async {
        let glances: [CGVector] = switch mood {
        case .failed: [CGVector(dx: 0, dy: 0.9), CGVector(dx: -0.6, dy: 0.8), CGVector(dx: 0.6, dy: 0.8)]
        default: [CGVector(dx: -1, dy: 0), CGVector(dx: -0.8, dy: -0.7), .zero, CGVector(dx: 1, dy: 0), CGVector(dx: 0.8, dy: -0.7)]
        }
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.6)))
            index = (index + 1) % glances.count
            pose.look = glances[index]
        }
    }

    /// Back and forth across the icon, eyes on where it's going, at 15 frames a second.
    private func runLoop() async {
        let start = Date.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.0 / 15))
            let t = Date.now.timeIntervalSince(start)
            pose.x = 3 * sin(2 * .pi * t / 2.2)
            pose.look = CGVector(dx: cos(2 * .pi * t / 2.2) >= 0 ? 1 : -1, dy: 0)
        }
    }
}
