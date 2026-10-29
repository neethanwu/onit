import SwiftUI

/// Where the list header keeps a place for Bead, in the notch's coordinate space.
struct BeadSlotKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// One black shape that grows out of the notch. Collapsed it is two short wings around the
/// hardware notch; open it is the full panel. Bead is drawn once, on top, and travels between
/// its spot in the left wing and its spot in the panel header.
struct NotchView: View {
    let store: JobStore
    @Bindable var model: NotchModel
    @State private var contentHeight: CGFloat = 320
    @State private var headerSlot = CGRect.zero
    @State private var resetToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var open: Bool { model.isExpanded }
    private var wing: CGFloat { NotchModel.wingWidth }
    private var collapsedWidth: CGFloat { model.notchWidth + wing * 2 }
    private var shapeSize: CGSize {
        open
            ? CGSize(width: NotchModel.panelWidth, height: model.notchHeight + contentHeight)
            : CGSize(width: collapsedWidth, height: model.notchHeight)
    }
    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = open ? 30 : 12
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .frame(width: shapeSize.width, height: shapeSize.height)
                // Moving between the list and a task's detail changes the height; let the black follow it.
                .animation(.onitSpring, value: contentHeight)

            panel
            collapsedTarget
            wingStatus
        }
        .frame(width: model.windowFrame.width, height: model.windowFrame.height, alignment: .top)
        .overlay(alignment: .topLeading) { bead }
        .coordinateSpace(.named(NotchModel.space))
        .onPreferenceChange(BeadSlotKey.self) { headerSlot = $0 }
        .environment(\.colorScheme, .dark)
        .onChange(of: open) { _, isOpen in
            guard !isOpen else { return }
            // Go back to the list once the panel has folded away, so it always reopens there.
            Task {
                try? await Task.sleep(for: .seconds(0.4))
                if !model.isExpanded { resetToken += 1 }
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        let top = model.notchHeight
        return VStack(spacing: 0) {
            Color.clear.frame(height: model.notchHeight)
            PopoverView(
                store: store,
                onDetailChange: { model.showingDetail = $0 },
                resetToken: resetToken,
                deepLink: (model.deepLink, model.deepLinkToken)
            )
                .environment(\.notchModel, model)
                .environment(\.notchStyle, true)
                .environment(\.panelWidth, NotchModel.panelWidth - 16)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(width: NotchModel.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height - top } action: { contentHeight = $0 }
        // The content arrives just after the shape starts to grow and leaves before it shrinks,
        // with a little blur so the crossfade reads as one thing settling into focus.
        .opacity(open ? 1 : 0)
        .blur(radius: open || reduceMotion ? 0 : 8)
        .animation(open ? .easeOut(duration: 0.24).delay(0.1) : .easeOut(duration: 0.12), value: open)
        .mask(alignment: .top) {
            shape.frame(width: shapeSize.width, height: shapeSize.height)
                .animation(.onitSpring, value: contentHeight)
        }
        .allowsHitTesting(open)
    }

    // MARK: - Collapsed

    private var collapsedTarget: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: collapsedWidth - wing)
                .contentShape(Rectangle())
                .onTapGesture { openPanel() }
            // The badge goes straight to the task it's counting.
            Color.clear
                .frame(width: wing)
                .contentShape(Rectangle())
                .onTapGesture { openPanel(at: problemTask?.id) }
        }
        .frame(height: model.notchHeight)
        .allowsHitTesting(!open)
        .help("onit")
    }

    /// The task the right wing's badge is about, when it shows one.
    private var problemTask: Job? {
        let active = store.visibleJobs.filter { !$0.isHidden }
        switch store.overallState {
        case .failed: return active.first { if case .failed = $0.state { true } else { false } }
        case .headsUp: return active.first { $0.schedule.hasOverlap }
        default: return nil
        }
    }

    private func openPanel(at taskID: String? = nil) {
        if let taskID {
            model.deepLink = taskID
            model.deepLinkToken += 1
        }
        withAnimation(.notchOpen) { model.isExpanded = true }
    }

    /// The wings stay in use while a task's detail is open, since the header has no Bead then.
    private var usesWings: Bool { !open || model.showingDetail || headerSlot == .zero }

    private var wingStatus: some View {
        let shown = usesWings
        return WingStatus(store: store)
            .frame(width: wing, height: model.notchHeight)
            .scaleEffect(shown ? 1 : 0.6)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .opacity(shown ? 1 : 0)
            .offset(x: (collapsedWidth - wing) / 2 - (shown ? 0 : wing * 0.6))
            .animation(shown ? .easeOut(duration: 0.22).delay(0.14) : .easeIn(duration: 0.12), value: shown)
            .allowsHitTesting(false)
    }

    // MARK: - Bead

    private var beadSize: CGFloat { usesWings ? NotchModel.wingBeadSize : NotchModel.headerBeadSize }

    /// Bead's center in this view: the middle of the left wing, or the header's slot on the list.
    private var beadCenter: CGPoint {
        if !usesWings {
            return CGPoint(x: headerSlot.midX, y: headerSlot.midY)
        }
        let leftEdge = (model.windowFrame.width - collapsedWidth) / 2
        return CGPoint(x: leftEdge + wing / 2, y: model.notchHeight / 2)
    }

    private var bead: some View {
        let center = beadCenter
        let inWing = usesWings
        // On a task's detail Bead flies back up to its wing, and back down when you return to the list.
        return BeadView(
            mood: BeadMood(store.overallState),
            size: beadSize,
            runRange: inWing ? 8 : 3,
            gaze: gaze(from: center),
            pokes: model.beadPokes
        )
        .offset(x: center.x - beadSize / 2, y: center.y - beadSize / 2)
        .animation(.notchOpen, value: inWing)
        .allowsHitTesting(false)
    }

    /// Points Bead's eyes at the pointer when it's within reach, scaled by how close it is.
    private func gaze(from center: CGPoint) -> CGVector? {
        guard let mouse = model.mouse, model.windowFrame != .zero else { return nil }
        let screenCenter = CGPoint(x: model.windowFrame.minX + center.x, y: model.windowFrame.maxY - center.y)
        let dx = mouse.x - screenCenter.x
        let dy = screenCenter.y - mouse.y
        let distance = hypot(dx, dy)
        guard distance < 420, distance > 1 else { return nil }
        let strength = min(1, distance / 60)
        return CGVector(dx: dx / distance * strength, dy: dy / distance * strength)
    }
}

/// One line of status in the right wing: when the next task runs, a running pulse, or a count of problems.
private struct WingStatus: View {
    let store: JobStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            switch store.overallState {
            case .failed:
                Badge(count: store.failedCount, color: BeadMood.failed.body)
            case .headsUp:
                Badge(count: store.overlapCount, color: BeadMood.headsUp.body)
            case .running:
                RunningDots()
            case .ok:
                if let next = store.nextUp(now: context.date) {
                    Text(TimeText.short(until: next.date, now: context.date))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                }
            case .empty:
                EmptyView()
            }
        }
    }
}

private struct Badge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(color))
    }
}

private struct RunningDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(BeadMood.onIt.body)
                        .frame(width: 4, height: 4)
                        .opacity(reduceMotion ? 0.8 : opacity(index: index, phase: phase))
                }
            }
        }
    }

    private func opacity(index: Int, phase: Double) -> Double {
        let distance = abs(phase * 3 - Double(index))
        return 0.25 + 0.75 * max(0, 1 - min(distance, 3 - distance))
    }
}
