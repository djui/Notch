import Foundation

/// Installs `notch-hook` and registers it with each agent's user-level hook config.
///
/// Existing hooks stay untouched. Notch's entries are appended rather than inserted, so the
/// positions Codex uses to remember trusted hooks do not shift, and the file as it was before
/// each change is kept as `<name>.notch-backup`.
enum AgentHookInstaller {
    enum Status: Equatable {
        /// The agent has never run on this Mac.
        case notDetected
        case notInstalled
        /// Some events or the hook script are missing.
        case partial
        case installed
        /// The config file is not valid JSON; Notch leaves it alone.
        case unreadable
    }

    enum InstallError: LocalizedError {
        case unreadableConfig(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let url):
                "\(url.path) is not a JSON object Notch can edit. Fix or remove it and try again."
            }
        }
    }

    static let scriptName = "notch-hook"
    static let timeout = 10

    static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func directory(home: URL = defaultHome) -> URL {
        home.appendingPathComponent(".config/notch", isDirectory: true)
    }

    static func scriptURL(home: URL = defaultHome) -> URL {
        directory(home: home).appendingPathComponent(scriptName)
    }

    static func socketURL(home: URL = defaultHome) -> URL {
        directory(home: home).appendingPathComponent("agent.sock")
    }

    static func status(for agent: CodingAgent, home: URL = defaultHome) -> Status {
        let fileManager = FileManager.default
        let configURL = agent.hookConfigURL(home: home)
        guard fileManager.fileExists(atPath: configURL.path) else {
            return fileManager.fileExists(atPath: agent.homeDirectory(home: home).path) ? .notInstalled : .notDetected
        }
        guard let root = try? loadConfig(configURL) else { return .unreadable }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let registered = agent.hookEvents.filter { event in
            entries(in: hooks[event], agent: agent).contains(where: isNotchHook)
        }
        if registered.isEmpty { return .notInstalled }
        if registered.count < agent.hookEvents.count
            || !fileManager.isExecutableFile(atPath: scriptURL(home: home).path) {
            return .partial
        }
        return .installed
    }

    static func install(_ agent: CodingAgent, home: URL = defaultHome) throws {
        try writeScript(home: home)
        let configURL = agent.hookConfigURL(home: home)
        var root = try loadConfig(configURL) ?? agent.emptyConfig
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let entry = agent.hookEntry(command: agent.hookCommand(scriptPath: scriptURL(home: home).path))
        for event in agent.hookEvents {
            hooks[event] = try adding(entry, to: hooks[event], agent: agent, configURL: configURL)
        }
        root["hooks"] = hooks
        try saveIfChanged(root, to: configURL)
    }

    static func uninstall(_ agent: CodingAgent, home: URL = defaultHome) throws {
        let configURL = agent.hookConfigURL(home: home)
        guard var root = try loadConfig(configURL), var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let remaining = removingNotchHooks(from: value, agent: agent)
            if let remaining, !remaining.isEmpty {
                hooks[event] = remaining
            } else if remaining != nil {
                hooks.removeValue(forKey: event)
            }
        }
        if hooks.isEmpty, agent == .claude {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try saveIfChanged(root, to: configURL)

        let stillUsed = CodingAgent.allCases.contains { [.installed, .partial].contains(status(for: $0, home: home)) }
        if !stillUsed {
            try? FileManager.default.removeItem(at: scriptURL(home: home))
        }
    }

    /// Keeps the installed script in step with this version of Notch.
    static func refreshScript(home: URL = defaultHome) {
        let installed = FileManager.default.fileExists(atPath: scriptURL(home: home).path)
            || CodingAgent.allCases.contains { status(for: $0, home: home) == .partial }
        guard installed else { return }
        try? writeScript(home: home)
    }

    static func writeScript(home: URL = defaultHome) throws {
        let url = scriptURL(home: home)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let contents = scriptContents(socketPath: socketURL(home: home).path)
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Forwards the hook payload on stdin plus where the agent runs. Always exits 0 and prints
    /// nothing, so it never blocks, denies, or annotates anything in the agent.
    static func scriptContents(socketPath: String) -> String {
        """
        #!/bin/sh
        # Sends Claude Code, Cursor, and Codex hook events to Notch.
        # Installed by Notch (Settings > Coding Agents), which rewrites this file on launch.
        # Usage: notch-hook [claude|cursor|codex] < hook-payload.json

        agent="${1:-}"
        if [ -z "$agent" ] && [ -n "${CURSOR_VERSION:-}" ]; then
          agent=cursor
        fi
        socket=\(shellQuoted(socketPath))
        if [ -z "$agent" ] || [ ! -S "$socket" ]; then
          cat >/dev/null
          exit 0
        fi
        tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
        /usr/bin/curl --silent --output /dev/null --max-time 2 \\
          --unix-socket "$socket" \\
          --header 'Content-Type: application/json' \\
          --header 'Expect:' \\
          --header "X-Notch-Host-Bundle: ${__CFBundleIdentifier:-}" \\
          --header "X-Notch-Term-Program: ${TERM_PROGRAM:-}" \\
          --header "X-Notch-Iterm-Session: ${ITERM_SESSION_ID:-}" \\
          --header "X-Notch-TTY: $tty" \\
          --data-binary @- \\
          "http://localhost/agents/$agent" >/dev/null 2>&1
        exit 0

        """
    }

    // MARK: - Config editing

    private static func adding(
        _ entry: [String: Any],
        to value: Any?,
        agent: CodingAgent,
        configURL: URL
    ) throws -> [[String: Any]] {
        guard let value else {
            return agent.groupsHooks ? [["hooks": [entry]]] : [entry]
        }
        guard var list = value as? [[String: Any]] else {
            throw InstallError.unreadableConfig(configURL)
        }
        if agent.groupsHooks {
            for index in list.indices {
                guard var hooks = list[index]["hooks"] as? [[String: Any]],
                      let position = hooks.firstIndex(where: isNotchHook)
                else { continue }
                hooks[position] = entry
                list[index]["hooks"] = hooks
                return list
            }
            list.append(["hooks": [entry]])
        } else if let position = list.firstIndex(where: isNotchHook) {
            list[position] = entry
        } else {
            list.append(entry)
        }
        return list
    }

    /// Nil when the value is not a hook list Notch understands, so it stays as it is.
    private static func removingNotchHooks(from value: Any, agent: CodingAgent) -> [[String: Any]]? {
        guard let list = value as? [[String: Any]] else { return nil }
        guard agent.groupsHooks else {
            return list.filter { !isNotchHook($0) }
        }
        return list.compactMap { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return group }
            let kept = hooks.filter { !isNotchHook($0) }
            if kept.count == hooks.count { return group }
            if kept.isEmpty { return nil }
            var group = group
            group["hooks"] = kept
            return group
        }
    }

    private static func entries(in value: Any?, agent: CodingAgent) -> [[String: Any]] {
        guard let list = value as? [[String: Any]] else { return [] }
        guard agent.groupsHooks else { return list }
        return list.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    private static func isNotchHook(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains("/notch/\(scriptName)") == true
    }

    /// Nil when the file does not exist. Throws when it exists but is not a JSON object.
    private static func loadConfig(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableConfig(url)
        }
        return root
    }

    /// Writes through symlinks (dotfile repos), keeps the file mode (Claude's settings are 0600),
    /// and backs up the previous contents.
    private static func saveIfChanged(_ root: [String: Any], to url: URL) throws {
        let fileManager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)

        var permissions: Any?
        if fileManager.fileExists(atPath: target.path) {
            let existing = try Data(contentsOf: target)
            if let old = try? JSONSerialization.jsonObject(with: existing) as? NSDictionary,
               old.isEqual(to: root) {
                return
            }
            permissions = try? fileManager.attributesOfItem(atPath: target.path)[.posixPermissions]
            try existing.write(to: target.appendingPathExtension("notch-backup"), options: .atomic)
        } else {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try data.write(to: target, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }

    static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@%")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

extension CodingAgent {
    /// Present once the agent has run on this Mac.
    func homeDirectory(home: URL = AgentHookInstaller.defaultHome) -> URL {
        switch self {
        case .claude: home.appendingPathComponent(".claude", isDirectory: true)
        case .cursor: home.appendingPathComponent(".cursor", isDirectory: true)
        case .codex: home.appendingPathComponent(".codex", isDirectory: true)
        }
    }

    func hookConfigURL(home: URL = AgentHookInstaller.defaultHome) -> URL {
        switch self {
        case .claude: homeDirectory(home: home).appendingPathComponent("settings.json")
        case .cursor, .codex: homeDirectory(home: home).appendingPathComponent("hooks.json")
        }
    }

    var hookConfigDisplayPath: String {
        switch self {
        case .claude: "~/.claude/settings.json"
        case .cursor: "~/.cursor/hooks.json"
        case .codex: "~/.codex/hooks.json"
        }
    }

    /// Only events that are safe to observe. Cursor's `before*` hooks block the action when a
    /// hook prints nothing, so Notch never registers them.
    var hookEvents: [String] {
        switch self {
        case .claude:
            [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Notification",
                "Stop", "StopFailure", "SubagentStop", "PreCompact", "SessionEnd",
            ]
        case .codex:
            [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse",
                "Stop", "SubagentStop", "PreCompact", "SessionEnd",
            ]
        case .cursor:
            ["sessionStart", "afterAgentResponse", "stop", "subagentStop", "preCompact", "sessionEnd"]
        }
    }

    /// Claude Code and Codex nest command hooks in matcher groups; Cursor lists them directly.
    var groupsHooks: Bool {
        self != .cursor
    }

    var emptyConfig: [String: Any] {
        switch self {
        case .cursor: ["version": 1, "hooks": [String: Any]()]
        case .claude, .codex: ["hooks": [String: Any]()]
        }
    }

    /// Cursor gets no argument in case it runs the command without a shell; the script
    /// recognizes it by `CURSOR_VERSION`.
    func hookCommand(scriptPath: String) -> String {
        let script = AgentHookInstaller.shellQuoted(scriptPath)
        switch self {
        case .claude, .codex: return "\(script) \(rawValue)"
        case .cursor: return script
        }
    }

    /// `async` keeps Claude Code and Codex from waiting on Notch at all.
    func hookEntry(command: String) -> [String: Any] {
        switch self {
        case .claude, .codex:
            ["type": "command", "command": command, "async": true, "timeout": AgentHookInstaller.timeout]
        case .cursor:
            ["command": command, "timeout": AgentHookInstaller.timeout]
        }
    }
}
