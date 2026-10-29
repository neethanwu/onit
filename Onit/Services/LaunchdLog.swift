import Foundation

/// launchd writes "service inactive: <label>" to the unified log each time a job's process exits.
/// Reading it once at launch fills in recent runs that happened before onit started watching.
enum LaunchdLog {
    static func recentRunEnds(for labels: Set<String>, window: String = "2h") -> [String: [Date]] {
        guard !labels.isEmpty else { return [:] }
        let result = Shell.run("/usr/bin/log", [
            "show", "--last", window, "--style", "compact",
            "--predicate", "process == \"launchd\" AND eventMessage CONTAINS \"service inactive: \"",
        ])
        return parse(result.output, labels: labels)
    }

    static func parse(_ output: String, labels: Set<String>, timeZone: TimeZone = .current) -> [String: [Date]] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var ends: [String: [Date]] = [:]
        for line in output.split(separator: "\n") {
            guard line.count > 23,
                  let marker = line.range(of: "service inactive: "),
                  let date = formatter.date(from: String(line.prefix(23)))
            else { continue }
            let label = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            guard labels.contains(label) else { continue }
            ends[label, default: []].append(date)
        }
        return ends
    }
}
