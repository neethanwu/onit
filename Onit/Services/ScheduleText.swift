import Foundation

/// Plain-English schedule summaries and next-run times.
enum ScheduleText {
    private static let weekdayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
    private static let shortWeekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func summary(_ schedule: Schedule) -> String {
        if let cron = schedule.cron { return cron.summary }
        if schedule.keepAlive { return "Always on · restarts if it stops" }

        var parts: [String] = []
        if let interval = schedule.interval { parts.append(intervalPhrase(interval)) }
        let calendarPhrases = schedule.calendar.map(calendarPhrase)
        if calendarPhrases.count > 3 {
            parts.append("\(calendarPhrases.count) set times")
        } else {
            parts.append(contentsOf: calendarPhrases)
        }
        if parts.isEmpty {
            if schedule.watchesPaths { return "When files change" }
            if schedule.runAtLoad { return "At login" }
            return "Only when started by hand"
        }
        return parts.enumerated()
            .map { $0.offset == 0 ? $0.element : lowercasedFirst($0.element) }
            .joined(separator: " + ")
    }

    /// Roughly how many runs a day the schedule produces, used to explain overlaps.
    static func runsPerDay(_ schedule: Schedule) -> Int {
        var total = 0
        if let interval = schedule.interval, interval > 0 { total += 86_400 / interval }
        for spec in schedule.calendar {
            let perHour = spec.minute == nil ? 60 : 1
            let hours = spec.hour == nil ? 24 : 1
            let daily = perHour * hours
            total += (spec.day == nil && spec.weekday == nil) ? daily : max(1, daily / 7)
        }
        return total
    }

    static func nextRun(for schedule: Schedule, lastRun: Date?, after now: Date, calendar: Calendar = .current) -> Date? {
        if let cron = schedule.cron { return cron.nextDate(after: now, calendar: calendar) }
        if schedule.keepAlive { return nil }

        var candidates: [Date] = schedule.calendar.compactMap { nextDate(for: $0, after: now, calendar: calendar) }
        if let interval = schedule.interval, let lastRun {
            var next = lastRun.addingTimeInterval(TimeInterval(interval))
            while next <= now { next.addTimeInterval(TimeInterval(interval)) }
            candidates.append(next)
        }
        return candidates.min()
    }

    static func nextDate(for spec: CalendarSpec, after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.minute = spec.minute
        components.hour = spec.hour
        components.day = spec.day
        components.month = spec.month
        if let weekday = spec.weekday { components.weekday = (weekday % 7) + 1 }
        if spec.minute == nil, spec.hour == nil, spec.day == nil, spec.weekday == nil, spec.month == nil {
            components.second = 0
        }
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }

    static func intervalPhrase(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "Every \(seconds) sec"
        case 60: return "Every minute"
        case 3600: return "Hourly"
        case 86_400: return "Daily"
        case 604_800: return "Weekly"
        default:
            if seconds % 86_400 == 0 { return "Every \(seconds / 86_400) days" }
            if seconds % 3600 == 0 { return "Every \(seconds / 3600) hours" }
            if seconds % 60 == 0 { return "Every \(seconds / 60) min" }
            return "Every \(seconds) sec"
        }
    }

    static func calendarPhrase(_ spec: CalendarSpec) -> String {
        guard let minute = spec.minute else {
            return spec.hour.map { "Every minute during \(TimeText.clock(hour: $0, minute: 0))" } ?? "Every minute"
        }
        guard let hour = spec.hour else {
            return minute == 0 ? "Hourly" : "Hourly at :\(String(format: "%02d", minute))"
        }
        let time = TimeText.clock(hour: hour, minute: minute)
        if let month = spec.month, let day = spec.day {
            let name = Calendar.current.monthSymbols[(month - 1) % 12]
            return "Every \(name) \(day) at \(time)"
        }
        if let day = spec.day { return "Monthly on the \(ordinal(day)) at \(time)" }
        if let weekday = spec.weekday { return "\(weekdayNames[weekday % 7]) at \(time)" }
        return "Daily at \(time)"
    }

    static func weekdayPhrase(_ weekdays: Set<Int>) -> String {
        let sorted = weekdays.sorted()
        if sorted == [1, 2, 3, 4, 5] { return "Weekdays" }
        if sorted == [0, 6] { return "Weekends" }
        if sorted.count == 1 { return weekdayNames[sorted[0] % 7] }
        return sorted.map { shortWeekdayNames[$0 % 7] }.joined(separator: ", ")
    }

    static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (1, let tens) where tens != 11: suffix = "st"
        case (2, let tens) where tens != 12: suffix = "nd"
        case (3, let tens) where tens != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }

    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
