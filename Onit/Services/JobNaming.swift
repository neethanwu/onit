import Foundation

/// Turns labels and commands into names a person would use.
enum JobNaming {
    private static let domainPrefixes: Set<String> = ["com", "org", "net", "io", "dev", "co", "app", "me", "local", "ai"]
    private static let interpreters: Set<String> = ["sh", "bash", "zsh", "fish", "python", "python3", "node", "ruby", "perl", "osascript", "env", "bun", "deno", "uv", "npx"]

    /// "com.example.claude-retro" → "Claude Retro", "dev.acme.sync.c633bcf9f9" → "Acme Sync"
    static func name(forLabel label: String) -> String {
        let label = label.hasPrefix("homebrew.mxcl.") ? String(label.dropFirst("homebrew.mxcl.".count)) : label
        var parts = label.split(separator: ".").map(String.init)
        if parts.count > 1, domainPrefixes.contains(parts[0].lowercased()) { parts.removeFirst() }
        if parts.count > 1, let last = parts.last, isHashLike(last) { parts.removeLast() }
        if parts.count > 1 {
            let rest = Array(parts.dropFirst())
            let restIsDescriptive = rest.count > 1 || rest[0].contains("-") || rest[0].contains("_") || rest[0].count > 6
            if restIsDescriptive { parts = rest }
        }
        return titleCase(parts.joined(separator: " "))
    }

    /// Name for a crontab entry from its command, e.g. "/Users/me/bin/notes-backup.sh >> log" → "Notes Backup".
    static func name(forCommand command: String) -> String {
        guard let script = scriptPath(inCommand: command) else { return "Cron job" }
        let base = URL(fileURLWithPath: script).deletingPathExtension().lastPathComponent
        return titleCase(base)
    }

    /// The file a job actually runs: the script handed to an interpreter, or the program itself.
    static func scriptPath(in arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let program = URL(fileURLWithPath: first).lastPathComponent
        if interpreters.contains(program) {
            if program == "sh" || program == "bash" || program == "zsh", arguments.count > 2, arguments[1] == "-c" {
                return scriptPath(inCommand: arguments[2])
            }
            return arguments.dropFirst().first { !$0.hasPrefix("-") && $0.contains("/") }
                ?? arguments.dropFirst().first { !$0.hasPrefix("-") }
        }
        return first
    }

    static func scriptPath(inCommand command: String) -> String? {
        // Use the last segment of a chain like "cd ~/x && ./run.sh >> log 2>&1".
        let segment = command.components(separatedBy: "&&").last ?? command
        let tokens = segment.split(whereSeparator: \.isWhitespace).map(String.init)
        var words: [String] = []
        for token in tokens {
            if token.hasPrefix(">") || token.hasPrefix("2>") || token == "|" { break }
            words.append(token)
        }
        return scriptPath(in: words)
    }

    /// "A script in retro", "The rsync program"
    static func whatItRuns(_ job: Job) -> String {
        let arguments = job.source == .cron ? ["/bin/sh", "-c", job.commandLine] : job.arguments
        guard let path = scriptPath(in: arguments) else { return "A command" }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let isScript = !url.pathExtension.isEmpty || path != arguments.first
        if isScript {
            let folder = meaningfulFolder(containing: url)
            return folder.map { "A script in \($0)" } ?? "A script"
        }
        return "The \(url.lastPathComponent) program"
    }

    private static let genericFolders: Set<String> = ["bin", "scripts", "script", "src", "system", "jobs", "cron"]

    /// The nearest parent folder whose name says something, skipping "bin", "_system" and the like.
    private static func meaningfulFolder(containing url: URL) -> String? {
        var folder = url.deletingLastPathComponent()
        for _ in 0..<3 {
            let name = folder.lastPathComponent
            if name.isEmpty || name == "/" { return nil }
            let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "_."))
            if !genericFolders.contains(trimmed.lowercased()) { return name }
            folder = folder.deletingLastPathComponent()
        }
        return folder.lastPathComponent
    }

    private static func isHashLike(_ text: String) -> Bool {
        text.count >= 6 && text.allSatisfy(\.isHexDigit) && text.contains(where: \.isNumber)
    }

    private static func titleCase(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
