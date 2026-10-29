import SwiftUI

/// Bead's mood follows the overall state, the same way the menu bar icon does.
enum BeadMood: Equatable {
    case dozing
    case onIt
    case headsUp
    case failed
    case nothing

    init(_ state: OverallState) {
        switch state {
        case .empty: self = .nothing
        case .ok: self = .dozing
        case .running: self = .onIt
        case .headsUp: self = .headsUp
        case .failed: self = .failed
        }
    }

    var body: Color {
        switch self {
        case .dozing: Color(white: 0.95)
        case .onIt: Color(red: 0.30, green: 0.64, blue: 1.0)
        case .headsUp: Color(red: 1.0, green: 0.70, blue: 0.14)
        case .failed: Color(red: 1.0, green: 0.35, blue: 0.37)
        case .nothing: .clear
        }
    }

    var eyes: Color {
        switch self {
        case .dozing: Color(white: 0.08)
        case .onIt: Color(red: 0.02, green: 0.16, blue: 0.29)
        case .headsUp: Color(red: 0.23, green: 0.15, blue: 0)
        case .failed: Color(red: 0.29, green: 0.05, blue: 0.06)
        case .nothing: .white.opacity(0.4)
        }
    }

    /// Dozing and on it keep moving; the others only move once when they arrive.
    var loops: Bool { self == .dozing || self == .onIt }
}

/// The notch mascot: a round body, two eyes and at most one sign.
struct BeadView: View {
    let mood: BeadMood
    let size: CGFloat
    /// In the wing Bead rolls back and forth; in the header it sways in place.
    var travel: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !mood.loops)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            figure
                .scaleEffect(breath(t))
                .offset(x: roll(t))
                .rotationEffect(.degrees(reduceMotion || mood != .onIt ? 0 : Double(roll(t) / max(travel, 2)) * 8))
        }
        .keyframeAnimator(initialValue: Nudge(), trigger: mood) { content, nudge in
            content.offset(x: nudge.x, y: nudge.y)
        } keyframes: { _ in
            let hop: CGFloat = reduceMotion || mood != .headsUp ? 0 : -3
            let shake: CGFloat = reduceMotion || mood != .failed ? 0 : 1.5
            KeyframeTrack(\.y) {
                CubicKeyframe(hop, duration: 0.14)
                SpringKeyframe(0, duration: 0.3, spring: .init(duration: 0.4, bounce: 0.3))
            }
            KeyframeTrack(\.x) {
                LinearKeyframe(shake, duration: 0.05)
                LinearKeyframe(-shake, duration: 0.05)
                LinearKeyframe(shake, duration: 0.05)
                LinearKeyframe(-shake, duration: 0.05)
                LinearKeyframe(shake, duration: 0.05)
                LinearKeyframe(0, duration: 0.05)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.25), value: mood)
        .accessibilityHidden(true)
    }

    private var figure: some View {
        ZStack {
            if mood == .onIt {
                SpeedLines()
                    .stroke(mood.body.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .frame(width: size * 0.3, height: size * 0.42)
                    .offset(x: -size * 0.62)
                    .transition(.opacity)
            }
            if mood == .nothing {
                Circle()
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: size * 0.06, dash: [size * 0.09, size * 0.1]))
            } else {
                Circle().fill(mood.body)
            }
            eyes
            if mood == .failed {
                Drop()
                    .fill(Color(red: 0.42, green: 0.77, blue: 1))
                    .frame(width: size * 0.2, height: size * 0.26)
                    .offset(x: size * 0.48, y: -size * 0.5)
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.3)))
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var eyes: some View {
        let gap = size * 0.32
        let dot = size * 0.17
        let lookAhead = mood == .onIt ? size * 0.05 : 0
        HStack(spacing: gap - dot) {
            ForEach(0..<2, id: \.self) { _ in
                if mood == .dozing {
                    ClosedEye()
                        .stroke(mood.eyes, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                        .frame(width: dot * 1.1, height: dot * 0.5)
                } else {
                    Circle().fill(mood.eyes).frame(width: dot, height: dot)
                }
            }
        }
        .offset(x: lookAhead, y: -size * 0.05)
    }

    private func breath(_ t: TimeInterval) -> CGFloat {
        guard mood == .dozing, !reduceMotion else { return 1 }
        return 1 + 0.02 * (1 - cos(2 * .pi * t / 4))
    }

    private func roll(_ t: TimeInterval) -> CGFloat {
        guard mood == .onIt, !reduceMotion else { return 0 }
        let reach = travel > 0 ? travel : 2
        return reach * sin(2 * .pi * t / 2.4)
    }

    private struct Nudge {
        var x: CGFloat = 0
        var y: CGFloat = 0
    }
}

private struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

private struct SpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, inset) in [0.15, 0.0, 0.15].enumerated() {
            let y = rect.minY + rect.height * CGFloat(index) / 2
            path.move(to: CGPoint(x: rect.minX + rect.width * inset, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct Drop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.minX - rect.width * 0.3, y: rect.maxY * 0.95))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.maxX + rect.width * 0.3, y: rect.maxY * 0.95))
        return path
    }
}
