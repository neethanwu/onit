import Foundation

enum JobSource: String, Codable, Sendable {
    case launchd
    case cron
}

/// One `StartCalendarInterval` entry. A nil field matches every value, as in launchd.
/// `weekday` uses launchd's numbering: 0 and 7 are Sunday.
struct CalendarSpec: Equatable, Sendable {
    var minute: Int?
    var hour: Int?
    var day: Int?
    var weekday: Int?
    var month: Int?
}

struct Schedule: Equatable, Sendable {
    var interval: Int?
    var calendar: [CalendarSpec] = []
    var cron: CronExpression?
    var keepAlive = false
    var runAtLoad = false
    var watchesPaths = false

    /// A launchd job with both an interval and calendar times runs on both, which is rarely intended.
    var hasOverlap: Bool { interval != nil && !calendar.isEmpty }
}

enum JobState: Equatable, Sendable {
    case running
    case succeeded
    case failed(exitCode: Int32)
    case paused
    case waiting
}

struct RunRecord: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date?
    var exitCode: Int32?
    /// False when the run started and ended between two polls, so only the end time is known.
    var durationKnown = true

    var duration: TimeInterval? {
        guard durationKnown, let end else { return nil }
        return end.timeIntervalSince(start)
    }
}

struct Job: Identifiable, Equatable, Sendable {
    var id: String
    var source: JobSource
    var label: String
    var name: String
    var schedule: Schedule
    var arguments: [String]
    var plistURL: URL?
    var cronLine: String?
    var stdoutPath: String?
    var stderrPath: String?
    var state: JobState = .waiting
    var pid: Int32?
    var lastExitCode: Int32?
    var totalRuns: Int?
    var lastRun: Date?
    /// Set by the scanner for vendor and app-bundled jobs; the user can override it.
    var looksSystemOwned = false
    var isHidden = false

    var isAlwaysOn: Bool { schedule.keepAlive }

    var logPath: String? { stdoutPath ?? stderrPath }

    var commandLine: String {
        if source == .cron, let command = arguments.last { return command }
        return arguments.joined(separator: " ")
    }
}
