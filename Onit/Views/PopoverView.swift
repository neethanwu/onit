import SwiftUI

struct PopoverView: View {
    let store: JobStore
    var onDetailChange: (Bool) -> Void = { _ in }
    /// Bumped by the notch when it closes, so it always reopens on the list.
    var resetToken = 0
    @State private var selectedID: String?
    @State private var menuHost = MenuHost()
    @State private var menuExtent: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelWidth) private var width
    @Environment(\.notchModel) private var notchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            ZStack(alignment: .top) {
                if let id = selectedID, let job = store.job(id: id) {
                    JobDetailView(store: store, job: job, now: context.date) {
                        navigate(to: nil, animated: true)
                    }
                    .transition(transition(edge: .trailing))
                } else {
                    JobListView(store: store, now: context.date) { job in
                        navigate(to: job.id, animated: true)
                    }
                    .transition(transition(edge: .leading))
                }
            }
        }
        .frame(width: width)
        // Behind an open menu the panel steps back, so the menu reads as the one thing in front.
        .opacity(menuHost.openID == nil ? 1 : 0.35)
        .animation(.easeOut(duration: 0.18), value: menuHost.openID)
        // A short list grows to hold an open menu instead of cutting it off, leaving the same
        // margin below the menu as beside it (the header's edge plus the notch's own padding).
        .frame(minHeight: menuExtent > 0 ? menuExtent + Metrics.edge : nil, alignment: .top)
        .overlayPreferenceValue(OpenMenuKey.self) { menu in
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if let menu {
                        // A tap anywhere else in the panel closes the menu.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: closeMenu)
                        menuCard(menu, button: proxy[menu.button])
                    }
                }
            }
        }
        .coordinateSpace(.named(MenuExtentKey.space))
        .onPreferenceChange(MenuExtentKey.self) { extent in
            withAnimation(.onitSpring) { menuExtent = extent }
        }
        .environment(\.menuHost, menuHost)
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard selectedID != nil else { return .ignored }
            // Keyboard navigation is instant; only pointer navigation slides.
            navigate(to: nil, animated: false)
            return .handled
        }
        .onChange(of: menuHost.openID) { notchModel?.menuOpen = $1 != nil }
        .onChange(of: selectedID) {
            menuHost.openID = nil
            onDetailChange($1 != nil)
        }
        .onChange(of: resetToken) {
            menuHost.openID = nil
            navigate(to: nil, animated: false)
        }
        // The menu bar panel also reopens on the list.
        .onDisappear { navigate(to: nil, animated: false) }
        .task { await store.refresh() }
    }

    /// The open menu, lined up under (or over) the button it belongs to.
    private func menuCard(_ menu: OpenMenu, button: CGRect) -> some View {
        let size = CGSize(width: NotchMenuCard.width, height: NotchMenuCard.height(of: menu.entries))
        let y = menu.upward ? button.minY - menu.gap - size.height : button.maxY + menu.gap
        return NotchMenuCard(entries: menu.entries, close: closeMenu)
            .frame(width: size.width, height: size.height)
            .preference(key: MenuExtentKey.self, value: y + size.height)
            .offset(x: button.maxX - size.width, y: y)
            // Grows out of the button it belongs to, not from its own center.
            .transition(.scale(scale: 0.92, anchor: menu.upward ? .bottomTrailing : .topTrailing).combined(with: .opacity))
    }

    private func closeMenu() {
        withAnimation(.easeIn(duration: 0.1)) { menuHost.openID = nil }
    }

    private func navigate(to id: String?, animated: Bool) {
        if animated {
            withAnimation(.onitSpring) { selectedID = id }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selectedID = id }
        }
    }

    private func transition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
