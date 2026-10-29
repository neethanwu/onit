import SwiftUI

@main
struct OnitApp: App {
    @State private var store: JobStore
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = JobStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: store.overallState, beadAngle: store.beadAngle))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
