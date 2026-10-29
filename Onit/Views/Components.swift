import SwiftUI

enum Metrics {
    static let popoverWidth: CGFloat = 360
    static let edge: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let statusColumn: CGFloat = 84
    static let dotColumn: CGFloat = 14
}

extension Animation {
    /// Shared by navigation and the popover's height change.
    static let onitSpring = Animation.spring(duration: 0.3, bounce: 0)
}

/// What a job's state looks like in the list and the detail header.
struct StatusStyle {
    var title: String
    var color: Color

    init(_ job: Job) {
        switch job.state {
        case .failed: self = StatusStyle(title: "Failed", color: .red)
        case .running: self = StatusStyle(title: "Running", color: .blue)
        case .succeeded: self = StatusStyle(title: "OK", color: .green)
        case .paused: self = StatusStyle(title: "Paused", color: .secondary)
        case .waiting: self = StatusStyle(title: job.source == .cron ? "Scheduled" : "Not run yet", color: .secondary)
        }
    }

    private init(title: String, color: Color) {
        self.title = title
        self.color = color
    }
}

struct StatusDot: View {
    let job: Job
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if job.state == .running {
                Circle()
                    .fill(Color.blue.opacity(0.22))
                    .frame(width: 14, height: 14)
                    .scaleEffect(breathing ? 1 : 0.7)
                    .opacity(breathing ? 1 : 0.5)
            }
            if job.state == .paused || job.state == .waiting {
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(StatusStyle(job).color)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: Metrics.dotColumn, height: 14)
        .onAppear {
            guard job.state == .running, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

struct SourceTag: View {
    let source: JobSource

    var body: some View {
        Text(source.rawValue)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(source == .cron ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 5)
            .padding(.vertical, 0.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(source == .cron ? AnyShapeStyle(Color.orange.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.6)))
            )
    }
}

/// A capsule that copies text and briefly turns into "Copied".
struct CopyButton: View {
    let title: String
    let tint: Color
    let text: () -> String
    let store: JobStore
    @State private var copied = false

    var body: some View {
        Button {
            store.copy(text())
            withAnimation(.easeOut(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.opacity)
                .foregroundStyle(copied ? Color.green : tint)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .tint((copied ? Color.green : tint).opacity(0.25))
        .controlSize(.small)
    }
}

/// A row in the facts list: label on the left, value on the right.
struct FactRow<Value: View>: View {
    let label: String
    var showsDivider = true
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value.fontWeight(.medium)
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().opacity(0.6) }
        }
    }
}

/// A press-to-scale style for plain rows.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(tint.map { AnyShapeStyle($0.opacity(0.14)) } ?? AnyShapeStyle(.quaternary.opacity(0.5)))
        )
    }
}

extension View {
    func card(tint: Color? = nil) -> some View {
        modifier(CardBackground(tint: tint))
    }
}
