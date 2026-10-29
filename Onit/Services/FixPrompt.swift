import Foundation

/// Prompts a person can paste into their coding agent to get a job fixed.
enum FixPrompt {
    static func forOverlap(_ job: Job) -> String {
        let interval = job.schedule.interval.map { ScheduleText.intervalPhrase($0).lowercased() } ?? "on an interval"
        let times = job.schedule.calendar.map(ScheduleText.calendarPhrase).joined(separator: ", ")
        return """
        My macOS launchd job "\(job.label)" has two schedules at once: StartInterval (\(interval)) and StartCalendarInterval (\(times)). launchd runs it on both, so it runs about \(ScheduleText.runsPerDay(job.schedule)) times a day.

        The job is defined in \(displayPath(job.plistURL?.path)).

        Please ask me which schedule I actually want, remove the other key from the plist, then reload the job with:
          launchctl bootout \(Shell.guiDomain) \(displayPath(job.plistURL?.path))
          launchctl bootstrap \(Shell.guiDomain) \(displayPath(job.plistURL?.path))
        """
    }

    static func forFailure(_ job: Job, explanation: FailureExplainer.Explanation, logTail: String) -> String {
        let definition: String
        switch job.source {
        case .launchd:
            definition = "a launchd job \"\(job.label)\" defined in \(displayPath(job.plistURL?.path))"
        case .cron:
            definition = "a crontab entry:\n  \(job.cronLine ?? job.commandLine)"
        }
        let exit = job.lastExitCode.map { "It last exited with code \($0)." } ?? ""
        let log = logTail.split(separator: "\n").suffix(30).joined(separator: "\n")
        let logSection = log.isEmpty ? "There is no log output." : "The end of its log (\(displayPath(job.logPath))):\n```\n\(log)\n```"

        return """
        A scheduled job on my Mac keeps failing. It's \(definition).

        It runs: \(job.commandLine)
        Schedule: \(ScheduleText.summary(job.schedule))
        \(exit)

        \(logSection)

        Please find out why it fails and fix it. Explain what you changed in plain language.
        """
    }

    private static func displayPath(_ path: String?) -> String {
        guard let path else { return "(unknown file)" }
        return path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
