import AppKit
import SwiftUI

@MainActor
@Observable
final class NotchModel {
    var isExpanded = false {
        didSet { if oldValue != isExpanded { onExpandChange?(isExpanded) } }
    }
    @ObservationIgnored var onExpandChange: ((Bool) -> Void)?
    /// Set by the popover so Escape steps back from a job's detail before closing the panel.
    @ObservationIgnored var showingDetail = false
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 32

    static let wingWidth: CGFloat = 44
    static let panelWidth: CGFloat = 380
}

/// A borderless panel pinned over the notch. It is always the size of the open panel;
/// everything outside the black shape is transparent, so clicks there reach the apps below.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let model = NotchModel()
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    private static let windowSize = CGSize(width: NotchModel.panelWidth + 40, height: 640)

    init(store: JobStore, display: DisplayController) {
        panel = NotchPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // No .fullScreenAuxiliary: a fullscreen app hides the notch area, so onit steps aside too.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false

        let root = NotchView(store: store, model: model)
            .environment(display)
        let hosting = FirstClickHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        model.onExpandChange = { [weak self] expanded in self?.expandChanged(expanded) }
    }

    func show(on geometry: NotchGeometry) {
        model.notchWidth = geometry.notchWidth
        model.notchHeight = geometry.notchHeight
        let origin = CGPoint(
            x: geometry.notchMidX - Self.windowSize.width / 2,
            y: geometry.screenFrame.maxY - Self.windowSize.height
        )
        panel.setFrame(CGRect(origin: origin, size: Self.windowSize), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        collapse()
        panel.orderOut(nil)
    }

    func collapse() {
        guard model.isExpanded else { return }
        withAnimation(.notchSpring) { model.isExpanded = false }
    }

    private func expandChanged(_ expanded: Bool) {
        if expanded {
            panel.makeKey()
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.collapse() }
            }
            // Escape closes the panel unless a job's detail is open, where it first goes back to the list.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, !self.model.showingDetail else { return false }
                    self.collapse()
                    return true
                }
                return handled ? nil : event
            }
        } else {
            for monitor in [outsideClickMonitor, escapeMonitor].compactMap({ $0 }) {
                NSEvent.removeMonitor(monitor)
            }
            outsideClickMonitor = nil
            escapeMonitor = nil
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The notch should react to the first click, even though onit is never the active app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Animation {
    static let notchSpring = Animation.spring(duration: 0.35, bounce: 0)
}

extension EnvironmentValues {
    /// Set inside the notch so the list header shows Bead and can share its geometry with the wing.
    @Entry var beadNamespace: Namespace.ID? = nil
    @Entry var panelWidth: CGFloat = Metrics.popoverWidth
}
