import SwiftUI

struct PopoverView: View {
    let store: JobStore
    var onDetailChange: (Bool) -> Void = { _ in }
    /// Bumped by the notch when it closes, so it always reopens on the list.
    var resetToken = 0
    /// Opens a task's detail without the slide, for the notch's badge.
    var deepLink: (id: String?, token: Int) = (nil, 0)
    @State private var selectedID: String?
    @State private var menuHost = MenuHost()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelWidth) private var width

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
        .background {
            // A tap on any empty part of the panel closes an open "more" menu.
            if menuHost.openID != nil {
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    withAnimation(.easeIn(duration: 0.1)) { menuHost.openID = nil }
                }
            }
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
        .onChange(of: selectedID) {
            menuHost.openID = nil
            onDetailChange($1 != nil)
        }
        .onChange(of: deepLink.token) {
            menuHost.openID = nil
            if let id = deepLink.id { navigate(to: id, animated: false) }
        }
        .onChange(of: resetToken) {
            menuHost.openID = nil
            navigate(to: nil, animated: false)
        }
        // The menu bar panel also reopens on the list.
        .onDisappear { navigate(to: nil, animated: false) }
        .task { await store.refresh() }
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
