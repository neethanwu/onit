import AppKit
import SwiftUI

@MainActor
@Observable
final class NotchModel {
    var isExpanded = false {
        didSet { if oldValue != isExpanded { onExpandChange?(isExpanded) } }
    }
    @ObservationIgnored var onExpandChange: ((Bool) -> Void)?
    /// Set by the popover so Escape steps back from a task's detail before closing the panel.
    var showingDetail = false
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 32

    /// Clicks on Bead in the panel header; each one makes it hop.
    var beadPokes = 0

    /// Pointer position in screen coordinates, so Bead can look at it.
    var mouse: CGPoint?
    var windowFrame: CGRect = .zero

    static let wingWidth: CGFloat = 44
    static let panelWidth: CGFloat = 380
    static let wingBeadSize: CGFloat = 18
    static let headerBeadSize: CGFloat = 34
    static let space = "notch"
}

/// A borderless panel pinned over the notch. It is always the size of the open panel;
/// everything outside the black shape is transparent, so clicks there reach the apps below.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let model = NotchModel()
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var mouseMonitors: [Any] = []

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
            .environment(Updates.shared)
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
        let frame = CGRect(origin: origin, size: Self.windowSize)
        panel.setFrame(frame, display: true)
        model.windowFrame = frame
        panel.orderFrontRegardless()
        trackPointer()
    }

    func hide() {
        collapse()
        panel.orderOut(nil)
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    /// Mouse moves anywhere on screen, so Bead can look at the pointer as it approaches.
    private func trackPointer() {
        guard mouseMonitors.isEmpty else { return }
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            if let last = model.mouse, hypot(last.x - location.x, last.y - location.y) < 2 { return }
            model.mouse = location
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { _ in
            MainActor.assumeIsolated { update() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            MainActor.assumeIsolated { update() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    func collapse() {
        guard model.isExpanded else { return }
        withAnimation(.notchClose) { model.isExpanded = false }
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
    /// Opening has a little give, like the island it's borrowed from; closing is quicker and settles flat.
    static let notchOpen = Animation.spring(duration: 0.45, bounce: 0.18)
    static let notchClose = Animation.spring(duration: 0.34, bounce: 0)
}

extension EnvironmentValues {
    @Entry var panelWidth: CGFloat = Metrics.popoverWidth
    /// True inside the notch, where controls are flat fills on black instead of Liquid Glass.
    @Entry var notchStyle = false
    @Entry var notchModel: NotchModel?
}
