import SwiftUI

struct PopoverView: View {
    let store: JobStore
    var onDetailChange: (Bool) -> Void = { _ in }
    @State private var selectedID: String?
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
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard selectedID != nil else { return .ignored }
            // Keyboard navigation is instant; only pointer navigation slides.
            navigate(to: nil, animated: false)
            return .handled
        }
        .onChange(of: selectedID) { onDetailChange($1 != nil) }
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
