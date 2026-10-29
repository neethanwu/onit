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

    /// Where Bead's eyes wander when nobody is pointing at it. Unit vectors, y down.
    fileprivate var glances: [CGVector] {
        let left = CGVector(dx: -1, dy: 0), right = CGVector(dx: 1, dy: 0)
        let upLeft = CGVector(dx: -0.8, dy: -0.7), upRight = CGVector(dx: 0.8, dy: -0.7)
        let down = CGVector(dx: 0, dy: 0.9), center = CGVector.zero
        switch self {
        case .headsUp: return [left, upLeft, center, right, upRight, center]
        case .failed: return [down, CGVector(dx: -0.6, dy: 0.8), down, CGVector(dx: 0.6, dy: 0.8)]
        case .nothing: return [left, center, right, center, CGVector(dx: 0, dy: -0.8)]
        case .dozing, .onIt: return [center]
        }
    }

    /// How long Bead holds each glance; a worried Bead looks around faster than a sad one.
    fileprivate var glanceHold: ClosedRange<Double> {
        switch self {
        case .headsUp: 0.9...1.8
        case .failed: 2.0...3.5
        default: 1.6...3.0
        }
    }
}

/// The notch mascot: a round body, two eyes and at most one sign.
/// It always has a little life in it: blinking, glancing around, breathing or running,
/// and when the pointer comes near it looks at the pointer instead.
struct BeadView: View {
    let mood: BeadMood
    let size: CGFloat
    /// Half the distance Bead runs back and forth while a task runs.
    var runRange: CGFloat = 0
    /// Direction to the pointer when it's close, scaled 0...1; nil lets Bead look around on its own.
    var gaze: CGVector?

    @State private var blink = false
    @State private var glance = CGVector.zero
    @State private var runSide: CGFloat = 1
    @State private var stride = false
    @State private var breathe = false
    @State private var float = false
    @State private var peek = false
    @State private var drip = false
    @State private var nudges = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        figure
            .scaleEffect(x: breathe ? 1.05 : 1, y: breathe ? 1.12 : 1, anchor: .bottom)
            .offset(y: stride ? -size * 0.07 : 0)
            .offset(y: float ? -size * 0.08 : size * 0.04)
            .offset(x: mood == .onIt ? runSide * runRange : 0)
            .keyframeAnimator(initialValue: Nudge(), trigger: nudges) { content, nudge in
                content.offset(x: nudge.x, y: nudge.y)
            } keyframes: { _ in
                let hop: CGFloat = reduceMotion || mood != .headsUp ? 0 : -size * 0.2
                let shake: CGFloat = reduceMotion || mood != .failed ? 0 : size * 0.09
                KeyframeTrack(\.y) {
                    CubicKeyframe(hop, duration: 0.14)
                    SpringKeyframe(0, duration: 0.3, spring: .init(duration: 0.4, bounce: 0.3))
                }
                KeyframeTrack(\.x) {
                    for value in [shake, -shake, shake, -shake, shake, 0] {
                        LinearKeyframe(value, duration: 0.05)
                    }
                }
            }
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.25), value: mood)
            .animation(.spring(duration: 0.25, bounce: 0), value: gaze)
            .task(id: mood) { await live() }
            .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private var figure: some View {
        ZStack {
            if mood == .onIt {
                SpeedLines()
                    .stroke(mood.body.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .frame(width: size * 0.3, height: size * 0.42)
                    .offset(x: -runSide * size * 0.62)
                    .transition(.opacity)
            }
            if mood == .nothing {
                Circle()
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: max(1, size * 0.06), dash: [size * 0.09, size * 0.1]))
            } else {
                Circle().fill(mood.body)
            }
            eyes
            if mood == .failed {
                Drop()
                    .fill(Color(red: 0.42, green: 0.77, blue: 1))
                    .frame(width: size * 0.2, height: size * 0.26)
                    // Every few seconds the drop runs down the side and a new one forms.
                    .offset(x: size * (drip ? 0.5 : 0.48), y: size * (drip ? -0.3 : -0.5))
                    .opacity(drip ? 0 : 1)
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.3)))
            }
        }
        .frame(width: size, height: size)
    }

    private var eyes: some View {
        let dot = size * 0.17
        let look = gaze ?? glance
        // A dozing Bead opens its eyes when the pointer comes close.
        let closed = mood == .dozing && gaze == nil
        return HStack(spacing: size * 0.32 - dot) {
            ForEach(0..<2, id: \.self) { index in
                // Now and then a dozing Bead opens one eye to check on things.
                if closed && !(peek && index == 1) {
                    ClosedEye()
                        .stroke(mood.eyes, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                        .frame(width: dot * 1.1, height: dot * 0.5)
                } else {
                    Capsule()
                        .fill(mood.eyes)
                        .frame(width: dot, height: blink ? dot * 0.15 : dot)
                }
            }
        }
        .frame(height: dot)
        .offset(x: look.dx * size * 0.08, y: -size * 0.05 + look.dy * size * 0.07)
    }

    // MARK: - Life

    /// Runs Bead's idle behaviour for the current mood until the mood changes.
    private func live() async {
        breathe = false
        stride = false
        float = false
        peek = false
        drip = false
        glance = .zero
        guard !reduceMotion else { return }
        nudges += 1

        await withTaskGroup(of: Void.self) { group in
            if mood != .dozing { group.addTask { await blinkLoop() } }
            switch mood {
            case .dozing:
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
                group.addTask { await peekLoop() }
            case .onIt:
                group.addTask { await runLoop() }
            case .headsUp:
                group.addTask { await glanceLoop() }
                group.addTask { await nudgeLoop(every: 7...11) }
            case .failed:
                group.addTask { await glanceLoop() }
                group.addTask { await dripLoop() }
                group.addTask { await nudgeLoop(every: 6...10) }
            case .nothing:
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { float = true }
                group.addTask { await glanceLoop() }
            }
        }
    }

    private func peekLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 7...11)))
            withAnimation(.easeOut(duration: 0.15)) { peek = true }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeIn(duration: 0.2)) { peek = false }
        }
    }

    private func dripLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...5)))
            withAnimation(.easeIn(duration: 0.7)) { drip = true }
            try? await Task.sleep(for: .seconds(0.9))
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drip = false }
        }
    }

    /// Repeats the mood's arrival move now and then: heads-up hops, failed shivers.
    private func nudgeLoop(every interval: ClosedRange<Double>) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: interval)))
            nudges += 1
        }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.4...5.2)))
            let times = Double.random(in: 0...1) < 0.2 ? 2 : 1
            for _ in 0..<times {
                withAnimation(.easeIn(duration: 0.06)) { blink = true }
                try? await Task.sleep(for: .seconds(0.09))
                withAnimation(.easeOut(duration: 0.1)) { blink = false }
                try? await Task.sleep(for: .seconds(0.14))
            }
        }
    }

    private func glanceLoop() async {
        var index = 0
        let glances = mood.glances
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: mood.glanceHold)))
            index = (index + 1) % glances.count
            withAnimation(.spring(duration: mood == .failed ? 0.6 : 0.3, bounce: 0)) { glance = glances[index] }
        }
    }

    /// Back and forth along the wing, looking where it's going, with a small jog in each step.
    private func runLoop() async {
        withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) { stride = true }
        let leg = 1.1
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: leg)) { runSide = -runSide }
            withAnimation(.spring(duration: 0.2, bounce: 0)) { glance = CGVector(dx: runSide, dy: 0) }
            try? await Task.sleep(for: .seconds(leg))
        }
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
