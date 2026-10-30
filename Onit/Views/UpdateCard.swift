import SwiftUI

/// An update, in onit's own panel: found, downloading, installing, up to date, or failed.
/// It sits under the header like the other cards, with Bead on it while there's work to do.
struct UpdateCard: View {
    let updates: Updates

    var body: some View {
        if updates.phase != .idle {
            HStack(alignment: .top, spacing: 10) {
                BeadGlyph(mood: mood, size: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if case .downloading(let progress) = updates.phase {
                        ProgressBar(progress: progress)
                            .padding(.top, 5)
                    }
                    actions
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    private var mood: BeadMood {
        switch updates.phase {
        case .failed: .failed
        case .upToDate: .dozing
        default: .onIt
        }
    }

    private var title: String {
        switch updates.phase {
        case .idle: ""
        case .checking: "Checking for updates…"
        case .upToDate: "You're on the latest version"
        case .available(let version): "onit \(version) is ready"
        case .downloading: "Downloading the update…"
        case .installing: "Installing, onit will reopen…"
        case .failed: "Couldn't update"
        }
    }

    private var detail: String? {
        switch updates.phase {
        case .available: "Update now and onit reopens in a few seconds."
        case .failed(let message): message
        default: nil
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updates.phase {
        case .available:
            HStack(spacing: 8) {
                Button("Update") { updates.install() }
                    .buttonStyle(UpdateButtonStyle(prominent: true))
                Button("Later") { updates.later() }
                    .buttonStyle(UpdateButtonStyle())
            }
        case .failed:
            Button("OK") { updates.dismiss() }
                .buttonStyle(UpdateButtonStyle())
        default:
            EmptyView()
        }
    }
}

/// A small capsule that hugs its label: blue for the main action, a quiet fill otherwise.
private struct UpdateButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PressBody(isPressed: configuration.isPressed, pressedScale: 0.95) { _ in
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .fixedSize()
                .surface(in: Capsule(), prominent: prominent, pressed: configuration.isPressed, notchFill: Color(white: 0.17))
        }
    }
}

/// A thin determinate bar, or a sliding one while the size isn't known yet.
private struct ProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let progress {
                    Capsule()
                        .fill(BeadMood.onIt.body)
                        .frame(width: max(4, proxy.size.width * progress))
                        .animation(.easeOut(duration: 0.2), value: progress)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule()
                            .fill(BeadMood.onIt.body)
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: proxy.size.width * (phase * 1.3 - 0.3))
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 4)
    }
}
