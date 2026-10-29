import Foundation

/// launchd only keeps a run count and the last exit code, so onit records each run itself
/// by watching jobs start and stop between polls. History begins when onit is installed.
@MainActor
final class RunHistory {
    private struct Snapshot {
        var pid: Int32?
        var runs: Int?
        var logModified: Date?
    }

    private static let keepPerJob = 50

    private(set) var runs: [String: [RunRecord]] = [:]
    private var snapshots: [String: Snapshot] = [:]
    private let fileURL: URL

    init(fileURL: URL = RunHistory.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("onit/history.json")
    }

    func records(for jobID: String) -> [RunRecord] {
        runs[jobID] ?? []
    }

    /// Compares each job with the previous poll and records starts and finishes.
    func observe(_ jobs: [Job], now: Date = .now) {
        var changed = false
        for job in jobs where !job.isAlwaysOn {
            let logModified = job.logPath.flatMap(Self.modificationDate)
            let current = Snapshot(pid: job.pid, runs: job.totalRuns, logModified: logModified)
            defer { snapshots[job.id] = current }
            guard let previous = snapshots[job.id] else { continue }

            switch job.source {
            case .launchd:
                changed = observeLaunchd(job, previous: previous, current: current, now: now) || changed
            case .cron:
                // cron gives no exit status; a fresh write to the job's log is the only sign it ran.
                if let modified = logModified, let before = previous.logModified, modified > before {
                    append(RunRecord(start: modified, end: modified, exitCode: nil, durationKnown: false), to: job.id)
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    private func observeLaunchd(_ job: Job, previous: Snapshot, current: Snapshot, now: Date) -> Bool {
        switch (previous.pid, current.pid) {
        case (nil, .some):
            append(RunRecord(start: now), to: job.id)
            return true
        case (.some, nil):
            if var list = runs[job.id], let index = list.lastIndex(where: { $0.end == nil }) {
                list[index].end = now
                list[index].exitCode = job.lastExitCode
                runs[job.id] = list
            } else {
                append(RunRecord(start: now, end: now, exitCode: job.lastExitCode, durationKnown: false), to: job.id)
            }
            return true
        case (nil, nil):
            // Started and finished between two polls.
            if let before = previous.runs, let after = current.runs, after > before {
                append(RunRecord(start: now, end: now, exitCode: job.lastExitCode, durationKnown: false), to: job.id)
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Adds runs found in the unified log for jobs onit has no history for yet.
    /// Only the latest one gets an exit code, since launchctl only reports the last.
    func backfill(jobID: String, ends: [Date], lastExitCode: Int32?) {
        guard runs[jobID]?.isEmpty ?? true, !ends.isEmpty else { return }
        let sorted = ends.sorted()
        runs[jobID] = sorted.enumerated().map { index, end in
            RunRecord(start: end, end: end, exitCode: index == sorted.count - 1 ? lastExitCode : nil, durationKnown: false)
        }
        save()
    }

    private func append(_ record: RunRecord, to jobID: String) {
        var list = runs[jobID] ?? []
        list.append(record)
        if list.count > Self.keepPerJob { list.removeFirst(list.count - Self.keepPerJob) }
        runs[jobID] = list
    }

    private static func modificationDate(_ path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: (path as NSString).expandingTildeInPath)
        return attributes?[.modificationDate] as? Date
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [RunRecord]].self, from: data)
        else { return }
        runs = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(runs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("onit: could not save run history: \(error.localizedDescription)")
        }
    }

    static func lastLogWrite(for job: Job) -> Date? {
        job.logPath.flatMap(modificationDate)
    }
}
