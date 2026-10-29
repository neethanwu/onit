import Foundation

/// Turns an exit code and the end of a log into a sentence someone who doesn't write code can act on.
enum FailureExplainer {
    struct Explanation: Equatable {
        var reason: String
        var rawLine: String?
    }

    private struct Rule {
        var patterns: [String]
        var reason: String
    }

    private static let rules: [Rule] = [
        Rule(patterns: ["no such file or directory", "not found: /", "does not exist"],
             reason: "A file or folder it needs is missing. It may have been moved, renamed or deleted."),
        Rule(patterns: ["command not found", "not found"],
             reason: "A program it relies on isn't installed, or can't be found from where the job runs."),
        Rule(patterns: ["operation not permitted", "permission denied", "not authorized"],
             reason: "macOS didn't allow it to access something. It may need permission in System Settings › Privacy & Security."),
        Rule(patterns: ["could not resolve host", "connection refused", "timed out", "network is unreachable", "name or service not known"],
             reason: "It couldn't reach the internet or a server it talks to."),
        Rule(patterns: ["rate limit", "unauthorized", "invalid api key", "authentication failed"],
             reason: "A service it uses turned it away. A key or login may have expired."),
        Rule(patterns: ["no space left"],
             reason: "Your disk is full, so it couldn't save its work."),
    ]

    static func explain(exitCode: Int32?, logTail: String) -> Explanation {
        let lines = logTail.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let errorLine = lines.last { line in
            let lower = line.lowercased()
            return lower.contains("error") || lower.contains("fail") || lower.contains("denied")
                || lower.contains("not found") || lower.contains("no such") || lower.contains("not permitted")
        } ?? lines.last

        let lowerTail = lines.suffix(20).joined(separator: "\n").lowercased()
        if let rule = rules.first(where: { rule in rule.patterns.contains { lowerTail.contains($0) } }) {
            return Explanation(reason: rule.reason, rawLine: errorLine.map(shorten))
        }

        let reason: String
        switch exitCode {
        case 126: reason = "The file it tries to run isn't allowed to run. It may need to be made executable."
        case 127: reason = "A program it relies on isn't installed, or can't be found from where the job runs."
        case -9, 137: reason = "macOS stopped it, possibly because it used too much memory."
        case -15, 143: reason = "It was stopped before it could finish."
        case let code?: reason = "It stopped with an error (code \(code))."
        case nil: reason = "It stopped with an error."
        }
        return Explanation(reason: reason, rawLine: errorLine.map(shorten))
    }

    static func readTail(ofFile path: String, bytes: Int = 8192) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard let handle = FileHandle(forReadingAtPath: expanded) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func shorten(_ line: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tidy = line.replacingOccurrences(of: home, with: "~")
        return tidy.count > 90 ? String(tidy.prefix(87)) + "…" : tidy
    }
}
