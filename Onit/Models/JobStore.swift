import AppKit
import Observation
import ServiceManagement

enum OverallState: Equatable {
    case empty
    case ok
    case running
    case headsUp
    case failed
}

@MainActor
@Observable
final class JobStore {
    private(set) var jobs: [Job] = []
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var beadAngle: Double = MenuBarIcon.restingAngle
    var showHidden = false

    @ObservationIgnored let history = RunHistory()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var spinTask: Task<Void, Never>?
    private var userHidden: Set<String>
    private var userShown: Set<String>

    private static let pollInterval: Duration = .seconds(10)
    private static let hiddenKey = "hiddenJobs"
    private static let shownKey = "shownJobs"

    init() {
        let defaults = UserDefaults.standard
        userHidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        userShown = Set(defaults.stringArray(forKey: Self.shownKey) ?? [])
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refresh()
            await self?.backfillFromSystemLog()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        let scanned = await Task.detached(priority: .utility) {
            LaunchdScanner.scan() + CronScanner.scan()
        }.value

        var updated = scanned.map { job in
            var job = job
            job.isHidden = userHidden.contains(job.id) || (job.looksSystemOwned && !userShown.contains(job.id))
            return job
        }
        history.observe(updated.filter { !$0.isHidden })
        updated = updated.map(applyHistory)

        jobs = updated
        lastUpdated = .now
        isRefreshing = false
        updateSpin()
    }

    private func backfillFromSystemLog() async {
        let candidates = jobs.filter { $0.source == .launchd && !$0.isHidden && !$0.isAlwaysOn && history.records(for: $0.id).isEmpty }
        let labels = Set(candidates.map(\.label))
        guard !labels.isEmpty else { return }
        let ends = await Task.detached(priority: .background) { LaunchdLog.recentRunEnds(for: labels) }.value
        for job in candidates {
            history.backfill(jobID: job.id, ends: ends[job.label] ?? [], lastExitCode: job.lastExitCode)
        }
        jobs = jobs.map(applyHistory)
    }

    private func applyHistory(_ job: Job) -> Job {
        var job = job
        let records = history.records(for: job.id)
        job.lastRun = records.last.map { $0.end ?? $0.start } ?? RunHistory.lastLogWrite(for: job)
        return job
    }

    // MARK: - Derived state

    var visibleJobs: [Job] {
        let now = Date.now
        return jobs
            .filter { showHidden || !$0.isHidden }
            .sorted { lhs, rhs in
                let left = sortRank(lhs), right = sortRank(rhs)
                if left != right { return left < right }
                let leftNext = nextRun(for: lhs, now: now) ?? .distantFuture
                let rightNext = nextRun(for: rhs, now: now) ?? .distantFuture
                if leftNext != rightNext { return leftNext < rightNext }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var activeJobs: [Job] { jobs.filter { !$0.isHidden } }

    var hiddenCount: Int { jobs.filter(\.isHidden).count }
    var failedCount: Int { activeJobs.filter { if case .failed = $0.state { true } else { false } }.count }
    var runningCount: Int { activeJobs.filter { $0.state == .running }.count }

    var overallState: OverallState {
        let active = activeJobs
        if active.isEmpty { return .empty }
        if failedCount > 0 { return .failed }
        if active.contains(where: \.schedule.hasOverlap) { return .headsUp }
        if active.contains(where: { $0.state == .running && !$0.isAlwaysOn }) { return .running }
        return .ok
    }

    func job(id: String) -> Job? {
        jobs.first { $0.id == id }
    }

    func nextRun(for job: Job, now: Date) -> Date? {
        guard job.state != .paused else { return nil }
        return ScheduleText.nextRun(for: job.schedule, lastRun: job.lastRun, after: now)
    }

    func nextUp(now: Date) -> (job: Job, date: Date)? {
        activeJobs
            .compactMap { job in nextRun(for: job, now: now).map { (job, $0) } }
            .min { $0.1 < $1.1 }
    }

    func runningSince(_ job: Job) -> Date? {
        guard job.state == .running else { return nil }
        return history.records(for: job.id).last { $0.end == nil }?.start
    }

    func records(for job: Job) -> [RunRecord] {
        history.records(for: job.id)
    }

    /// How many of the most recent runs failed back to back.
    func failureStreak(for job: Job) -> Int {
        var streak = 0
        for record in history.records(for: job.id).reversed() {
            guard let code = record.exitCode, code != 0 else { break }
            streak += 1
        }
        if case .failed = job.state { return max(streak, 1) }
        return streak
    }

    func lastSuccess(for job: Job) -> Date? {
        history.records(for: job.id).last { $0.exitCode == 0 }.map { $0.end ?? $0.start }
    }

    private func sortRank(_ job: Job) -> Int {
        switch job.state {
        case .failed: 0
        case .running where !job.isAlwaysOn: 1
        case .paused: 4
        default: job.schedule.hasOverlap ? 2 : 3
        }
    }

    // MARK: - Actions

    func runNow(_ job: Job) async {
        switch job.source {
        case .launchd:
            let target = "\(Shell.guiDomain)/\(job.label)"
            let plistPath = job.plistURL?.path
            await Task.detached {
                if Shell.launchctl("kickstart", target).status != 0, let plistPath {
                    Shell.launchctl("bootstrap", Shell.guiDomain, plistPath)
                    Shell.launchctl("kickstart", target)
                }
            }.value
        case .cron:
            let command = job.commandLine
            await Task.detached { Shell.spawn(command) }.value
        }
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func setPaused(_ job: Job, paused: Bool) async {
        guard job.source == .launchd, let plistPath = job.plistURL?.path else { return }
        let target = "\(Shell.guiDomain)/\(job.label)"
        await Task.detached {
            if paused {
                Shell.launchctl("disable", target)
                Shell.launchctl("bootout", target)
            } else {
                Shell.launchctl("enable", target)
                Shell.launchctl("bootstrap", Shell.guiDomain, plistPath)
            }
        }.value
        await refresh()
    }

    func setHidden(_ job: Job, hidden: Bool) {
        if hidden {
            userHidden.insert(job.id)
            userShown.remove(job.id)
        } else {
            userHidden.remove(job.id)
            if job.looksSystemOwned { userShown.insert(job.id) }
        }
        let defaults = UserDefaults.standard
        defaults.set(Array(userHidden), forKey: Self.hiddenKey)
        defaults.set(Array(userShown), forKey: Self.shownKey)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].isHidden = hidden }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openLog(_ job: Job) {
        guard let path = job.logPath else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open([url], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealDefinition(_ job: Job) {
        if let url = job.plistURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("onit: could not change login item: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Menu bar animation

    private func updateSpin() {
        let shouldSpin = overallState == .running && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldSpin, spinTask == nil {
            spinTask = Task { [weak self] in
                let fps = 12.0
                let step = 360.0 / (MenuBarIcon.lapSeconds * fps)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1 / fps))
                    guard let self else { return }
                    self.beadAngle = (self.beadAngle + step).truncatingRemainder(dividingBy: 360)
                }
            }
        } else if !shouldSpin, let task = spinTask {
            task.cancel()
            spinTask = nil
            beadAngle = MenuBarIcon.restingAngle
        }
    }
}
