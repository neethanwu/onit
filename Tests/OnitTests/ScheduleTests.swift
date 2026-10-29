import Foundation
import Testing
@testable import Onit

struct CronExpressionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    @Test func summaries() {
        #expect(CronExpression("*/30 * * * *")?.summary == "Every 30 min")
        #expect(CronExpression("0 * * * *")?.summary == "Hourly")
        #expect(CronExpression("15 * * * *")?.summary == "Hourly at :15")
        #expect(CronExpression("0 2 * * *")?.summary == "Daily at 2:00 AM")
        #expect(CronExpression("0 9 * * 1")?.summary == "Mondays at 9:00 AM")
        #expect(CronExpression("30 18 * * 1-5")?.summary == "Weekdays at 6:30 PM")
        #expect(CronExpression("0 0 1 * *")?.summary == "Monthly on the 1st at 12:00 AM")
        #expect(CronExpression("@daily")?.summary == "Daily at 12:00 AM")
    }

    @Test func rejectsInvalid() {
        #expect(CronExpression("61 * * * *") == nil)
        #expect(CronExpression("* * *") == nil)
        #expect(CronExpression("@reboot") == nil)
    }

    @Test func nextDate() throws {
        let cron = try #require(CronExpression("0 2 * * *"))
        let next = cron.nextDate(after: date("2026-10-28T13:37:00Z"), calendar: calendar)
        #expect(next == date("2026-10-29T02:00:00Z"))

        let weekly = try #require(CronExpression("0 9 * * mon"))
        // 2026-10-28 is a Wednesday.
        #expect(weekly.nextDate(after: date("2026-10-28T13:37:00Z"), calendar: calendar) == date("2026-11-02T09:00:00Z"))
    }

    @Test func dayOfMonthOrWeekday() throws {
        // Both day fields restricted: either matching is enough.
        let cron = try #require(CronExpression("0 0 1 * fri"))
        #expect(cron.nextDate(after: date("2026-10-28T00:00:00Z"), calendar: calendar) == date("2026-10-30T00:00:00Z"))
    }
}

struct LaunchdScheduleTests {
    @Test func overlapIsDescribed() {
        var schedule = Schedule()
        schedule.interval = 3600
        schedule.calendar = [CalendarSpec(minute: 0, hour: 8)]
        #expect(schedule.hasOverlap)
        #expect(ScheduleText.summary(schedule) == "Hourly + daily at 8:00 AM")
        #expect(ScheduleText.runsPerDay(schedule) == 25)
    }

    @Test func calendarPhrases() {
        #expect(ScheduleText.calendarPhrase(CalendarSpec(minute: 0, hour: 9, weekday: 1)) == "Mondays at 9:00 AM")
        #expect(ScheduleText.calendarPhrase(CalendarSpec(minute: 30)) == "Hourly at :30")
        #expect(ScheduleText.intervalPhrase(1800) == "Every 30 min")
    }

    @Test func keepAlive() {
        var schedule = Schedule()
        schedule.keepAlive = true
        #expect(ScheduleText.summary(schedule) == "Always on · restarts if it stops")
    }
}

struct NamingTests {
    @Test func labels() {
        #expect(JobNaming.name(forLabel: "com.example.claude-retro") == "Claude Retro")
        #expect(JobNaming.name(forLabel: "dev.acme.sync.c633bcf9f9") == "Acme Sync")
        #expect(JobNaming.name(forLabel: "inbox-triage") == "Inbox Triage")
        #expect(JobNaming.name(forLabel: "homebrew.mxcl.mongodb-community") == "Mongodb Community")
    }

    @Test func commands() {
        #expect(JobNaming.name(forCommand: "/Users/me/bin/notes-backup.sh >> /tmp/log 2>&1") == "Notes Backup")
        #expect(JobNaming.name(forCommand: "cd ~/agents && python3 triage.py") == "Triage")
    }

    @Test func whatItRuns() {
        let job = Job(id: "x", source: .launchd, label: "x", name: "x", schedule: Schedule(),
                      arguments: ["/bin/zsh", "/Users/me/ai/retro/_system/run.sh", "launchd"])
        #expect(JobNaming.whatItRuns(job) == "A script in retro")
    }
}

struct ParsingTests {
    @Test func launchctlList() {
        let output = "PID\tStatus\tLabel\n-\t0\tcom.a\n123\t-15\tcom.b\n"
        let parsed = LaunchdScanner.parseList(output)
        #expect(parsed["com.a"]?.pid == nil)
        #expect(parsed["com.b"]?.pid == 123)
        #expect(parsed["com.b"]?.status == -15)
    }

    @Test func disabled() {
        let output = "\tdisabled services = {\n\t\t\"com.a\" => enabled\n\t\t\"com.b\" => disabled\n\t}\n"
        #expect(LaunchdScanner.parseDisabled(output) == ["com.b"])
    }

    @Test func crontab() {
        let crontab = """
        SHELL=/bin/zsh
        # nightly notes backup
        0 2 * * * /Users/me/bin/backup.sh >> /Users/me/logs/backup.log 2>&1
        # 0 3 * * * /old/disabled.sh
        */30 * * * * cd ~/agents && ./triage.sh
        @reboot /usr/local/bin/thing
        """
        let jobs = CronScanner.parse(crontab)
        #expect(jobs.count == 2)
        #expect(jobs[0].name == "Nightly notes backup")
        #expect(jobs[0].stdoutPath == "/Users/me/logs/backup.log")
        #expect(jobs[1].name == "Triage")
        #expect(jobs[1].stdoutPath == nil)
    }

    @Test func unifiedLog() {
        let output = """
        Timestamp               Ty Process[PID:TID]
        2026-10-28 22:33:30.148 Df launchd[1:2d161c2] [gui/501 [100018]:] service inactive: com.me.retro
        2026-10-28 23:33:30.423 Df launchd[1:2d5d5bf] [gui/501 [100018]:] service inactive: com.other.thing
        """
        let ends = LaunchdLog.parse(output, labels: ["com.me.retro"], timeZone: TimeZone(identifier: "UTC")!)
        #expect(ends["com.me.retro"]?.count == 1)
        #expect(ends["com.other.thing"] == nil)
    }

    @Test func failureReasons() {
        let missing = FailureExplainer.explain(exitCode: 1, logTail: "rsync: mkdir \"/x/Backups\" failed: No such file or directory (2)")
        #expect(missing.reason.hasPrefix("A file or folder it needs is missing"))
        let killed = FailureExplainer.explain(exitCode: -9, logTail: "")
        #expect(killed.reason.contains("macOS stopped it"))
    }
}
