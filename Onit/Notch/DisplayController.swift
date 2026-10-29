import AppKit
import Observation

/// Decides whether onit lives in the notch or in the menu bar. Only one is ever shown.
/// The notch is the default; when the notch can't be used, the menu bar icon takes over until it can.
@MainActor
@Observable
final class DisplayController {
    enum Preference: String {
        case notch
        case menuBar
    }

    var preference: Preference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey)
            update()
        }
    }

    private(set) var notchAvailable = false

    var showsNotch: Bool { preference == .notch && notchAvailable }
    var showsMenuBarIcon: Bool { !showsNotch }

    @ObservationIgnored private let store: JobStore
    @ObservationIgnored private var notch: NotchWindowController?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    private static let preferenceKey = "displayMode"

    init(store: JobStore) {
        self.store = store
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey)
        preference = saved.flatMap(Preference.init) ?? .notch
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    func update() {
        let geometry = NotchGeometry.current()
        notchAvailable = geometry != nil
        if showsNotch, let geometry {
            if notch == nil { notch = NotchWindowController(store: store, display: self) }
            notch?.show(on: geometry)
        } else {
            notch?.hide()
        }
    }
}

/// Where the notch is on the built-in display, if there is one.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var notchMidX: CGFloat

    static func current() -> NotchGeometry? {
        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { continue }
            let frame = screen.frame
            return NotchGeometry(
                screenFrame: frame,
                notchWidth: frame.width - left.width - right.width,
                notchHeight: screen.safeAreaInsets.top,
                notchMidX: frame.minX + left.width + (frame.width - left.width - right.width) / 2
            )
        }
        return nil
    }
}
