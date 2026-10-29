import Foundation

/// Short, human time strings used across the popover.
enum TimeText {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func clock(hour: Int, minute: Int) -> String {
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
    }

    /// "just now", "7m ago", "11h ago", "3d ago"
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }

    /// "in 23 min", "in 3 hr", "in 2 days"
    static func until(_ date: Date, now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        switch seconds {
        case ..<60: return "in under a min"
        case ..<3600: return "in \(Int((seconds / 60).rounded(.up))) min"
        case ..<86_400: return "in \(Int((seconds / 3600).rounded())) hr"
        default:
            let days = Int((seconds / 86_400).rounded())
            return days == 1 ? "in 1 day" : "in \(days) days"
        }
    }

    /// "for 3 days", "for 2 hr"
    static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "for \(max(1, Int(seconds / 60))) min"
        case ..<86_400: return "for \(Int(seconds / 3600)) hr"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "for 1 day" : "for \(days) days"
        }
    }

    /// "Today at 2:00 PM", "Tomorrow at 2:00 AM", "Friday at 9:00 AM", "Mon, Nov 3 at 9:00 AM"
    static func dayAndTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow at \(time)"
        }
        if date.timeIntervalSince(now) < 6 * 86_400 { return "\(weekdayFormatter.string(from: date)) at \(time)" }
        return "\(dayFormatter.string(from: date)) at \(time)"
    }

    /// "Today, 1:00 PM", "Yesterday, 2:00 AM", "Mon, Oct 26"
    static func runDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(clock(date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(clock(date))"
        }
        return dayFormatter.string(from: date)
    }

    static func shortDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// "3 sec", "1 min", "2 hr"
    static func duration(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "\(max(1, Int(seconds.rounded()))) sec"
        case ..<3600: return "\(Int((seconds / 60).rounded())) min"
        default: return "\(Int((seconds / 3600).rounded())) hr"
        }
    }
}
