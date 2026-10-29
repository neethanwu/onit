import SwiftUI

enum MenuEntry: Identifiable {
    case item(title: String, systemImage: String, checked: Bool? = nil, shortcut: KeyEquivalent? = nil, action: () -> Void)
    case divider(id: String)

    var id: String {
        switch self {
        case let .item(title, _, _, _, _): title
        case let .divider(id): "divider-\(id)"
        }
    }
}

/// Which "more" menu is open, so a tap elsewhere in the panel can close it.
@MainActor
@Observable
final class MenuHost {
    var openID: String?
}

extension EnvironmentValues {
    @Entry var menuHost: MenuHost?
}

/// The "···" button. In the menu bar it opens the system menu; in the notch, where a system
/// menu would float off the black panel, it opens a matching dark menu inside the panel.
struct MoreButton: View {
    let id: String
    var size = Metrics.controlSize
    var opensUpward = false
    let entries: () -> [MenuEntry]

    @Environment(\.notchStyle) private var notchStyle
    @Environment(\.menuHost) private var host

    var body: some View {
        if notchStyle, let host {
            notchButton(host)
        } else {
            systemMenu
        }
    }

    private func notchButton(_ host: MenuHost) -> some View {
        let open = host.openID == id
        let anchor: UnitPoint = opensUpward ? .bottomTrailing : .topTrailing
        return Button {
            withAnimation(open ? .easeIn(duration: 0.1) : .spring(duration: 0.22, bounce: 0)) {
                host.openID = open ? nil : id
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(GlassCircleButtonStyle(size: size))
        .help("More")
        .overlay(alignment: opensUpward ? .bottomTrailing : .topTrailing) {
            if open {
                NotchMenuCard(entries: entries()) {
                    withAnimation(.easeIn(duration: 0.1)) { host.openID = nil }
                }
                .fixedSize()
                .offset(y: opensUpward ? -(size + 6) : size + 6)
                // Grows out of the button it belongs to, not from its own center.
                .transition(.scale(scale: 0.92, anchor: anchor).combined(with: .opacity))
            }
        }
        .zIndex(open ? 10 : 0)
    }

    private var systemMenu: some View {
        Menu {
            ForEach(entries()) { entry in
                switch entry {
                case .divider:
                    Divider()
                case let .item(title, systemImage, checked, shortcut, action):
                    if let checked {
                        Toggle(isOn: Binding(get: { checked }, set: { _ in action() })) {
                            Label(title, systemImage: systemImage)
                        }
                    } else if let shortcut {
                        Button(action: action) { Label(title, systemImage: systemImage) }
                            .keyboardShortcut(shortcut)
                    } else {
                        Button(action: action) { Label(title, systemImage: systemImage) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(GlassCircleButtonStyle(size: size))
        .fixedSize()
        .help("More")
    }
}

private struct NotchMenuCard: View {
    let entries: [MenuEntry]
    let close: () -> Void

    var body: some View {
        FluidHoverStack(items: entries, cornerRadius: 7, isActivatable: { entry in
            if case .item = entry { return true }
            return false
        }, onActivate: run) { entry, _ in
            switch entry {
            case .divider:
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
            case let .item(title, systemImage, checked, shortcut, _):
                NotchMenuRow(title: title, systemImage: systemImage, checked: checked, shortcut: shortcut) { run(entry) }
            }
        }
        .padding(5)
        .frame(width: 214)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    private func run(_ entry: MenuEntry) {
        guard case let .item(_, _, _, _, action) = entry else { return }
        close()
        action()
    }
}

private struct NotchMenuRow: View {
    let title: String
    let systemImage: String
    let checked: Bool?
    let shortcut: KeyEquivalent?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 8)
                if checked == true {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if let shortcut {
                    Text("⌘\(String(shortcut.character).uppercased())")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle(pressedScale: 0.98))
    }
}
