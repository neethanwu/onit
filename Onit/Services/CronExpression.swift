import Foundation

/// A five-field crontab schedule: minute, hour, day of month, month, day of week.
struct CronExpression: Equatable, Sendable {
    let raw: String
    let minutes: Set<Int>
    let hours: Set<Int>
    let days: Set<Int>
    let months: Set<Int>
    /// 0 is Sunday; a 7 in the source is folded into 0.
    let weekdays: Set<Int>
    let daysRestricted: Bool
    let weekdaysRestricted: Bool
    private let fields: [String]

    private static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *",
        "@annually": "0 0 1 1 *",
        "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *",
        "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    init?(_ expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        let source = Self.macros[trimmed.lowercased()] ?? trimmed
        let fields = source.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5,
              let minutes = Self.parse(fields[0], range: 0...59),
              let hours = Self.parse(fields[1], range: 0...23),
              let days = Self.parse(fields[2], range: 1...31),
              let months = Self.parse(fields[3], range: 1...12, names: Self.monthNames, nameOffset: 1),
              let weekdays = Self.parse(fields[4], range: 0...7, names: Self.dayNames, nameOffset: 0)
        else { return nil }

        self.raw = trimmed
        self.fields = fields
        self.minutes = minutes
        self.hours = hours
        self.days = days
        self.months = months
        self.weekdays = Set(weekdays.map { $0 == 7 ? 0 : $0 })
        self.daysRestricted = fields[2] != "*"
        self.weekdaysRestricted = fields[4] != "*"
    }

    private static func parse(_ field: String, range: ClosedRange<Int>, names: [String] = [], nameOffset: Int = 0) -> Set<Int>? {
        var result = Set<Int>()
        for part in field.lowercased().split(separator: ",") {
            let pieces = part.split(separator: "/", maxSplits: 1)
            var step = 1
            if pieces.count == 2 {
                guard let value = Int(pieces[1]), value > 0 else { return nil }
                step = value
            }
            let base = String(pieces[0])
            var lower = range.lowerBound
            var upper = range.upperBound
            if base != "*" {
                let bounds = base.split(separator: "-", maxSplits: 1).map(String.init)
                guard let first = value(bounds[0], names: names, offset: nameOffset) else { return nil }
                lower = first
                if bounds.count == 2 {
                    guard let last = value(bounds[1], names: names, offset: nameOffset) else { return nil }
                    upper = last
                } else {
                    upper = pieces.count == 2 ? range.upperBound : first
                }
            }
            guard range.contains(lower), range.contains(upper), lower <= upper else { return nil }
            result.formUnion(stride(from: lower, through: upper, by: step))
        }
        return result.isEmpty ? nil : result
    }

    private static func value(_ text: String, names: [String], offset: Int) -> Int? {
        if let number = Int(text) { return number }
        guard let index = names.firstIndex(of: text) else { return nil }
        return index + offset
    }

    func matchesDay(_ components: DateComponents) -> Bool {
        guard let day = components.day, let month = components.month, let weekday = components.weekday else { return false }
        guard months.contains(month) else { return false }
        let dayMatch = days.contains(day)
        let weekdayMatch = weekdays.contains(weekday - 1)
        // Cron's rule: when both day fields are restricted, either one matching is enough.
        switch (daysRestricted, weekdaysRestricted) {
        case (true, true): return dayMatch || weekdayMatch
        case (true, false): return dayMatch
        case (false, true): return weekdayMatch
        case (false, false): return true
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let sortedHours = hours.sorted()
        let sortedMinutes = minutes.sorted()
        var dayStart = calendar.startOfDay(for: date)
        for _ in 0..<1500 {
            let components = calendar.dateComponents([.day, .month, .weekday], from: dayStart)
            if matchesDay(components) {
                for hour in sortedHours {
                    for minute in sortedMinutes {
                        guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) else { continue }
                        if candidate > date { return candidate }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            dayStart = next
        }
        return nil
    }

    var summary: String {
        let minuteField = fields[0]
        let hourField = fields[1]
        let everyDay = !daysRestricted && !weekdaysRestricted && fields[3] == "*"

        if everyDay, hourField == "*", minuteField.hasPrefix("*/"), let step = Int(minuteField.dropFirst(2)) {
            return step == 1 ? "Every minute" : "Every \(step) min"
        }
        if everyDay, minuteField == "*", hourField == "*" {
            return "Every minute"
        }
        if everyDay, hourField == "*", minutes.count == 1, let minute = minutes.first {
            return minute == 0 ? "Hourly" : "Hourly at :\(String(format: "%02d", minute))"
        }
        if everyDay, hourField.hasPrefix("*/"), let step = Int(hourField.dropFirst(2)), minutes.count == 1 {
            return "Every \(step) hours"
        }
        guard minutes.count == 1, let minute = minutes.first, (1...3).contains(hours.count), fields[3] == "*" else {
            return "Custom: \(raw)"
        }
        let times = hours.sorted().map { TimeText.clock(hour: $0, minute: minute) }.joined(separator: ", ")
        if everyDay { return "Daily at \(times)" }
        if weekdaysRestricted, !daysRestricted {
            return "\(ScheduleText.weekdayPhrase(weekdays)) at \(times)"
        }
        if daysRestricted, !weekdaysRestricted, days.count == 1, let day = days.first {
            return "Monthly on the \(ScheduleText.ordinal(day)) at \(times)"
        }
        return "Custom: \(raw)"
    }
}
