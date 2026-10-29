import SwiftUI

/// The notch, either as two short wings around the hardware notch or as the dropped-down panel.
struct NotchView: View {
    let store: JobStore
    @Bindable var model: NotchModel
    @Namespace private var beadSpace

    var body: some View {
        VStack(spacing: 0) {
            if model.isExpanded {
                expanded
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                    ))
            } else {
                collapsed
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var mood: BeadMood { BeadMood(store.overallState) }

    private var collapsed: some View {
        HStack(spacing: 0) {
            BeadView(mood: mood, size: 18, travel: 7)
                .matchedGeometryEffect(id: "bead", in: beadSpace)
                .frame(width: NotchModel.wingWidth)
            Color.clear.frame(width: model.notchWidth)
            WingStatus(store: store)
                .frame(width: NotchModel.wingWidth)
        }
        .frame(height: model.notchHeight)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .fill(.black)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.notchSpring) { model.isExpanded = true }
        }
        .help("onit")
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notchHeight)
            PopoverView(store: store) { model.showingDetail = $0 }
                .environment(\.beadNamespace, beadSpace)
                .environment(\.panelWidth, NotchModel.panelWidth - 16)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(width: NotchModel.panelWidth)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous)
                .fill(.black)
        )
    }
}

/// One line of status in the right wing: when the next job runs, a running pulse, or a count of problems.
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
