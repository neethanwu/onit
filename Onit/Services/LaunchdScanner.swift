import Foundation

/// Reads the user's LaunchAgents and asks launchctl how each one is doing.
enum LaunchdScanner {
    static var agentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    }

    private static let systemPrefixes = ["com.apple.", "homebrew.mxcl."]

    static func scan() -> [Job] {
        let files = (try? FileManager.default.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: nil)) ?? []
        let loaded = loadedJobs()
        let disabled = disabledLabels()

        return files
            .filter { $0.pathExtension == "plist" }
            .compactMap { parse(plistAt: $0) }
            .map { job in
                var job = job
                applyStatus(to: &job, loaded: loaded[job.label], disabled: disabled.contains(job.label))
                return job
            }
    }

    static func parse(plistAt url: URL) -> Job? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String
        else { return nil }

        var arguments = plist["ProgramArguments"] as? [String] ?? []
        if let program = plist["Program"] as? String {
            if arguments.isEmpty { arguments = [program] } else { arguments[0] = program }
        }

        var schedule = Schedule()
        schedule.interval = plist["StartInterval"] as? Int
        if let dict = plist["StartCalendarInterval"] as? [String: Any] {
            schedule.calendar = [calendarSpec(dict)]
        } else if let list = plist["StartCalendarInterval"] as? [[String: Any]] {
            schedule.calendar = list.map(calendarSpec)
        }
        if let keepAlive = plist["KeepAlive"] as? Bool {
            schedule.keepAlive = keepAlive
        } else if plist["KeepAlive"] is [String: Any] {
            schedule.keepAlive = true
        }
        schedule.runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        schedule.watchesPaths = plist["WatchPaths"] != nil || plist["QueueDirectories"] != nil

        var job = Job(
            id: "launchd:\(label)",
            source: .launchd,
            label: label,
            name: JobNaming.name(forLabel: label),
            schedule: schedule,
            arguments: arguments,
            plistURL: url,
            stdoutPath: plist["StandardOutPath"] as? String,
            stderrPath: plist["StandardErrorPath"] as? String
        )
        job.looksSystemOwned = looksSystemOwned(label: label, program: arguments.first)
        if plist["Disabled"] as? Bool == true { job.state = .paused }
        return job
    }

    /// Vendor agents and helpers that ship inside apps are not the user's own scheduled work.
    static func looksSystemOwned(label: String, program: String?) -> Bool {
        if systemPrefixes.contains(where: label.hasPrefix) { return true }
        guard let program else { return false }
        let appSupport = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").path
        return program.contains(".app/Contents/") || program.hasPrefix(appSupport)
    }

    private static func calendarSpec(_ dict: [String: Any]) -> CalendarSpec {
        CalendarSpec(
            minute: dict["Minute"] as? Int,
            hour: dict["Hour"] as? Int,
            day: dict["Day"] as? Int,
            weekday: dict["Weekday"] as? Int,
            month: dict["Month"] as? Int
        )
    }

    // MARK: - launchctl

    struct Loaded {
        var pid: Int32?
        var status: Int32
    }

    /// Parses `launchctl list`: PID, last exit status and label for every loaded job.
    static func loadedJobs() -> [String: Loaded] {
        parseList(Shell.launchctl("list").output)
    }

    static func parseList(_ output: String) -> [String: Loaded] {
        var result: [String: Loaded] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            result[String(columns[2])] = Loaded(pid: Int32(columns[0]), status: Int32(columns[1]) ?? 0)
        }
        return result
    }

    static func disabledLabels() -> Set<String> {
        parseDisabled(Shell.launchctl("print-disabled", Shell.guiDomain).output)
    }

    static func parseDisabled(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            labels.insert(parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return labels
    }

    /// Reads the run count from `launchctl print`, which `list` doesn't include.
    static func runCount(label: String) -> Int? {
        let output = Shell.launchctl("print", "\(Shell.guiDomain)/\(label)").output
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("runs = ") { return Int(trimmed.dropFirst("runs = ".count)) }
        }
        return nil
    }

    private static func applyStatus(to job: inout Job, loaded: Loaded?, disabled: Bool) {
        guard let loaded, !disabled else {
            job.state = .paused
            return
        }
        job.pid = loaded.pid
        job.lastExitCode = loaded.status
        if !job.looksSystemOwned { job.totalRuns = runCount(label: job.label) }

        if loaded.pid != nil {
            job.state = .running
        } else if job.totalRuns == 0 {
            job.state = .waiting
        } else if loaded.status == 0 {
            job.state = .succeeded
        } else {
            job.state = .failed(exitCode: loaded.status)
        }
    }
}
