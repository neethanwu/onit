import Foundation

/// Reads the user's crontab.
enum CronScanner {
    static func scan() -> [Job] {
        let result = Shell.run("/usr/bin/crontab", ["-l"])
        guard result.status == 0 else { return [] }
        return parse(result.output)
    }

    static func parse(_ crontab: String) -> [Job] {
        var jobs: [Job] = []
        var pendingComment: String?

        for rawLine in crontab.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                pendingComment = nil
                continue
            }
            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                // A commented-out entry is not a name.
                pendingComment = text.isEmpty || CronExpression(String(text.split(separator: " ").prefix(5).joined(separator: " "))) != nil ? nil : text
                continue
            }
            if isEnvironmentAssignment(line) { continue }

            guard let (expression, command) = split(line), let cron = CronExpression(expression) else {
                pendingComment = nil
                continue
            }

            var schedule = Schedule()
            schedule.cron = cron
            let name = pendingComment.map(cleanComment) ?? JobNaming.name(forCommand: command)
            var job = Job(
                id: "cron:\(stableHash(line))",
                source: .cron,
                label: line,
                name: name,
                schedule: schedule,
                arguments: ["/bin/sh", "-c", command],
                cronLine: line,
                stdoutPath: logPath(in: command)
            )
            job.state = .waiting
            jobs.append(job)
            pendingComment = nil
        }
        return jobs
    }

    /// Splits an entry into its schedule and command; returns nil for `@reboot`, which has no schedule.
    private static func split(_ line: String) -> (String, String)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        if let first = tokens.first, first.hasPrefix("@") {
            guard first.lowercased() != "@reboot", tokens.count > 1 else { return nil }
            return (String(first), tokens.dropFirst().joined(separator: " "))
        }
        guard tokens.count > 5 else { return nil }
        return (tokens.prefix(5).joined(separator: " "), tokens.dropFirst(5).joined(separator: " "))
    }

    private static func isEnvironmentAssignment(_ line: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// The file a command appends its output to, if any.
    static func logPath(in command: String) -> String? {
        let tokens = command.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            var target: String?
            if token == ">>" || token == ">" || token == "1>>" || token == "1>" {
                target = index + 1 < tokens.count ? tokens[index + 1] : nil
            } else if token.hasPrefix(">>") {
                target = String(token.dropFirst(2))
            } else if token.hasPrefix(">"), !token.hasPrefix(">&") {
                target = String(token.dropFirst())
            }
            if let target, !target.isEmpty, target != "/dev/null", !target.hasPrefix("&") {
                return (target as NSString).expandingTildeInPath
            }
        }
        return nil
    }

    private static func cleanComment(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// FNV-1a, so a job keeps its id (and history) across launches.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
