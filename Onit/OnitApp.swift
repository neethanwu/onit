import SwiftUI

@main
struct OnitApp: App {
    @State private var store: JobStore
    @State private var display: DisplayController
    @State private var menuBead: MenuBarBead
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = JobStore()
        let display = DisplayController(store: store)
        store.start()
        // The notch window needs NSApp, which isn't ready until the app finishes launching.
        DispatchQueue.main.async { display.start() }
        _store = State(initialValue: store)
        _display = State(initialValue: display)
        let menuBead = MenuBarBead()
        menuBead.follow(store)
        _menuBead = State(initialValue: menuBead)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { display.showsMenuBarIcon }, set: { _ in })) {
            PopoverView(store: store)
                .environment(display)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: menuBead.mood, pose: menuBead.pose))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
