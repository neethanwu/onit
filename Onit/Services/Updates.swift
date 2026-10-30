import AppKit
import Observation
import Sparkle

/// Keeps onit up to date. Sparkle checks the appcast, downloads and installs; instead of its
/// own windows, onit shows each step as a card in its panel, in the notch or the menu bar.
@MainActor
@Observable
final class Updates: NSObject, SPUUserDriver {
    static let shared = Updates()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double?)
        case installing
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    /// A new version is waiting for the person to choose Update or Later.
    var hasUpdate: Bool {
        if case .available = phase { return true }
        return false
    }

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var reply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var acknowledge: (() -> Void)?
    @ObservationIgnored private var expectedLength: UInt64 = 0
    @ObservationIgnored private var receivedLength: UInt64 = 0

    /// Starts the daily background check. A build without a feed (a local `make run`) stays quiet.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do {
            try updater.start()
            self.updater = updater
        } catch {
            NSLog("onit: updater didn't start: \(error.localizedDescription)")
        }
    }

    var canCheck: Bool { updater?.canCheckForUpdates ?? false }

    func check() {
        updater?.checkForUpdates()
    }

    func install() {
        reply?(.install)
        reply = nil
    }

    func later() {
        reply?(.dismiss)
        reply = nil
        phase = .idle
    }

    func dismiss() {
        acknowledge?()
        acknowledge = nil
        phase = .idle
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns automatic checks on, so this is only a fallback.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        self.reply = reply
        if state.stage == .installing {
            // Already downloaded and waiting from an earlier session: finish it.
            install()
            phase = .installing
        } else {
            phase = .available(version: appcastItem.displayVersionString)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledge = acknowledgement
        phase = .upToDate
        Task {
            try? await Task.sleep(for: .seconds(3))
            if phase == .upToDate { dismiss() }
        }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledge = acknowledgement
        phase = .failed(message: error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        phase = .downloading(progress: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard expectedLength > 0 else { return }
        phase = .downloading(progress: min(1, Double(receivedLength) / Double(expectedLength)))
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .installing
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The person already chose Update; go straight on and relaunch.
        reply(.install)
        phase = .installing
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        phase = .idle
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        reply = nil
        if case .failed = phase { return }
        if phase != .upToDate { phase = .idle }
    }
}
