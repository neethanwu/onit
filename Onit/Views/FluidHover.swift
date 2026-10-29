import SwiftUI

/// One hover highlight per list that glides to the row nearest the pointer, so moving down a
/// list never flickers dark between rows. A fresh entry fades in where the pointer is instead
/// of sliding over from wherever the highlight was last, and a click in a gap goes to the lit row.
struct FluidHoverStack<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var spacing: CGFloat = 0
    var cornerRadius: CGFloat = 8
    var isActivatable: (Item) -> Bool = { _ in true }
    let onActivate: (Item) -> Void
    @ViewBuilder let row: (Item, Bool) -> Row

    @State private var space = UUID()
    @State private var rects: [Item.ID: CGRect] = [:]
    @State private var active: Item.ID?
    @State private var visible = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchStyle) private var notchStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(items) { item in
                row(item, visible && active == item.id)
                    .modifier(FrameReporter(space: space) { rects[item.id] = $0 })
            }
        }
        .background(alignment: .topLeading) { highlight }
        .coordinateSpace(.named(space))
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            switch phase {
            case .active(let point): hover(at: point)
            case .ended: withAnimation(.easeIn(duration: 0.06)) { visible = false }
            }
        }
        // Row buttons take their own clicks; this only catches clicks in the gaps between them.
        .onTapGesture {
            if visible, let active, let item = items.first(where: { $0.id == active }) { onActivate(item) }
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if let active, let rect = rects[active] {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    /// A surface-relative tint: white on dark, black on light.
    private var fill: Color {
        notchStyle || colorScheme == .dark ? .white.opacity(0.07) : .black.opacity(0.05)
    }

    private func hover(at point: CGPoint) {
        guard let nearest = nearestItem(to: point) else { return }
        if !visible {
            var place = Transaction()
            place.disablesAnimations = true
            withTransaction(place) { active = nearest }
            withAnimation(.easeOut(duration: 0.08)) { visible = true }
        } else if nearest != active {
            if reduceMotion {
                active = nearest
            } else {
                withAnimation(.spring(duration: 0.1, bounce: 0)) { active = nearest }
            }
        }
    }

    private func nearestItem(to point: CGPoint) -> Item.ID? {
        items
            .filter(isActivatable)
            .compactMap { item in rects[item.id].map { (item.id, $0) } }
            .min { distance(point, $0.1) < distance(point, $1.1) }?
            .0
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

/// Reports a view's frame in a named space. Kept non-generic so its geometry closure can be Sendable.
private struct FrameReporter: ViewModifier {
    let space: UUID
    let report: (CGRect) -> Void

    func body(content: Content) -> some View {
        let name = space
        return content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(name)) } action: { report($0) }
    }
}
