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

/// The open notch menu, handed up to the panel, which draws it above everything else
/// and dims what's behind it.
struct OpenMenu {
    let entries: [MenuEntry]
    let upward: Bool
    let gap: CGFloat
    let button: Anchor<CGRect>
}

struct OpenMenuKey: PreferenceKey {
    static var defaultValue: OpenMenu? { nil }
    static func reduce(value: inout OpenMenu?, nextValue: () -> OpenMenu?) {
        value = value ?? nextValue()
    }
}

/// How far down the panel an open menu reaches, so a short panel can grow to hold it.
struct MenuExtentKey: PreferenceKey {
    static let space = "menu-host"
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
    /// Where the button's top sits in the panel, to tell whether an upward menu would fit.
    @State private var buttonTop: CGFloat = .infinity

    var body: some View {
        if notchStyle, let host {
            notchButton(host)
        } else {
            systemMenu
        }
    }

    private func notchButton(_ host: MenuHost) -> some View {
        let open = host.openID == id
        let menuEntries = entries()
        // Opens upward only when the panel has room above; otherwise down, where the panel can grow.
        let upward = opensUpward && buttonTop - 6 - NotchMenuCard.height(of: menuEntries) >= 0
        return Button {
            withAnimation(open ? .easeIn(duration: 0.1) : .spring(duration: 0.22, bounce: 0)) {
                host.openID = open ? nil : id
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(GlassCircleButtonStyle(size: size))
        .help("More")
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(MenuExtentKey.space)).minY } action: { buttonTop = $0 }
        .anchorPreference(key: OpenMenuKey.self, value: .bounds) { bounds in
            open ? OpenMenu(entries: menuEntries, upward: upward, gap: 6, button: bounds) : nil
        }
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

struct NotchMenuCard: View {
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
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    static let width: CGFloat = 214

    /// The card's height, worked out from its rows so the direction is known before it opens.
    static func height(of entries: [MenuEntry]) -> CGFloat {
        entries.reduce(10) { total, entry in
            if case .divider = entry { return total + 9 }
            return total + 26
        }
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
