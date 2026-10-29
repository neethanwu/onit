import SwiftUI

enum Metrics {
    static let popoverWidth: CGFloat = 320
    static let edge: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let statusColumn: CGFloat = 72
    static let dotColumn: CGFloat = 12
    static let controlSize: CGFloat = 26
    static let actionHeight: CGFloat = 28
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
                    .frame(width: 12, height: 12)
                    .scaleEffect(breathing ? 1 : 0.7)
                    .opacity(breathing ? 1 : 0.5)
            }
            if job.state == .paused || job.state == .waiting {
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(StatusStyle(job).color)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: Metrics.dotColumn, height: 12)
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
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(source == .cron ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 4)
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
            // Both labels are laid out at once so the capsule never changes size.
            ZStack(alignment: .leading) {
                label(title, icon: "doc.on.doc", iconColor: tint).opacity(copied ? 0 : 1)
                label("Copied", icon: "checkmark", iconColor: .green).opacity(copied ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(PressableRowStyle())
    }

    private func label(_ text: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
        }
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
            value
        }
        .font(.system(size: 12))
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().opacity(0.6) }
        }
    }
}

/// The round glass control used for refresh, back and "more", so all three match in size.
struct GlassCircleButtonStyle: ButtonStyle {
    var size = Metrics.controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Capsule glass buttons in the action bar, all the same height.
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.actionHeight)
            .contentShape(Capsule())
            .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Icon and title with a tighter gap and a smaller icon than the default label.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .semibold))
            configuration.title
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
