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
            // The capsule hugs its label and animates its width; the fixed height keeps the panel still.
            Group {
                if copied {
                    label("Copied", icon: "checkmark", iconColor: .green)
                } else {
                    label(title, icon: "doc.on.doc", iconColor: tint)
                }
            }
            .transition(.opacity)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .fixedSize()
            .surface(in: Capsule(), notchFill: Color(white: 0.17))
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
        PressBody(isPressed: configuration.isPressed, pressedScale: 0.88) { hovering in
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .surface(in: Circle(), pressed: configuration.isPressed, hovering: hovering)
        }
    }
}

/// Press and hover feedback shared by every button: it dips quickly when pressed and springs
/// back with a little overshoot on release, and lightens while the pointer is over it.
struct PressBody<Content: View>: View {
    let isPressed: Bool
    var pressedScale: CGFloat = 0.95
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .scaleEffect(isPressed ? pressedScale : 1)
            .animation(isPressed ? .easeOut(duration: 0.1) : .spring(duration: 0.35, bounce: 0.45), value: isPressed)
            .onHover { inside in
                withAnimation(inside ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2)) { hovering = inside }
            }
    }
}

/// Capsule glass buttons in the action bar, all the same height.
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PressBody(isPressed: configuration.isPressed, pressedScale: 0.95) { hovering in
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.actionHeight)
                .contentShape(Capsule())
                .surface(in: Capsule(), prominent: prominent, pressed: configuration.isPressed, hovering: hovering)
                .opacity(isEnabled ? 1 : 0.6)
        }
    }
}

/// Liquid Glass in the menu bar popover; flat fills on the notch's black, where glass has nothing to refract.
struct Surface<S: Shape>: ViewModifier {
    let shape: S
    var prominent = false
    var pressed = false
    var hovering = false
    var notchFill: Color?
    @Environment(\.notchStyle) private var notchStyle

    func body(content: Content) -> some View {
        if notchStyle {
            content.background(shape.fill(flatFill))
        } else {
            content.glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: shape)
        }
    }

    private var flatFill: Color {
        let lift = pressed ? 0.12 : hovering ? 0.07 : 0
        if prominent { return Color(red: 0.04, green: 0.52, blue: 1).mix(with: .white, by: lift) }
        return (notchFill ?? Color(white: 0.11)).mix(with: .white, by: lift)
    }
}

extension View {
    func surface<S: Shape>(in shape: S, prominent: Bool = false, pressed: Bool = false, hovering: Bool = false, notchFill: Color? = nil) -> some View {
        modifier(Surface(shape: shape, prominent: prominent, pressed: pressed, hovering: hovering, notchFill: notchFill))
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
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : .spring(duration: 0.35, bounce: 0.4), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    var tint: Color?
    @Environment(\.notchStyle) private var notchStyle

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: notchStyle ? 16 : Metrics.cardRadius, style: .continuous)
                .fill(fill)
        )
    }

    private var fill: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint.opacity(0.14)) }
        return notchStyle ? AnyShapeStyle(Color(white: 0.08)) : AnyShapeStyle(.quaternary.opacity(0.5))
    }
}

extension View {
    func card(tint: Color? = nil) -> some View {
        modifier(CardBackground(tint: tint))
    }
}
