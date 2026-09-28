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
    static let decisionTimeout = 60

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
        let script = scriptURL(home: home).path
        var registered = 0
        var current = 0
        for event in agent.hookEvents {
            guard let entry = entries(in: hooks[event], agent: agent).first(where: isNotchHook) else { continue }
            registered += 1
            // An entry written by an older Notch still works but misses newer behavior.
            if (entry as NSDictionary).isEqual(to: agent.hookEntry(event: event, scriptPath: script)) {
                current += 1
            }
        }
        if registered == 0 { return .notInstalled }
        if current < agent.hookEvents.count || !fileManager.isExecutableFile(atPath: script) {
            return .partial
        }
        return .installed
    }

    static func install(_ agent: CodingAgent, home: URL = defaultHome) throws {
        try writeScript(home: home)
        let configURL = agent.hookConfigURL(home: home)
        var root = try loadConfig(configURL) ?? agent.emptyConfig
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let script = scriptURL(home: home).path
        for event in agent.hookEvents {
            let entry = agent.hookEntry(event: event, scriptPath: script)
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

        let stillUsed = CodingAgent.hookable.contains { [.installed, .partial].contains(status(for: $0, home: home)) }
        if !stillUsed, !commandLineToolInstalled(home: home) {
            try? FileManager.default.removeItem(at: scriptURL(home: home))
        }
    }

    /// Keeps the installed script in step with this version of Notch.
    static func refreshScript(home: URL = defaultHome) {
        let installed = FileManager.default.fileExists(atPath: scriptURL(home: home).path)
            || CodingAgent.hookable.contains { status(for: $0, home: home) == .partial }
        guard installed else { return }
        try? writeScript(home: home)
        if commandLineToolInstalled(home: home) {
            try? writeCommandLineTool(home: home)
        }
    }

    // MARK: - Command-line tool

    static func commandLineToolURL(home: URL = defaultHome) -> URL {
        directory(home: home).appendingPathComponent("notch")
    }

    /// `~/.local/bin` when it exists, since that is usually on PATH already.
    static func commandLineLinkURL(home: URL = defaultHome) -> URL? {
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bin.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return bin.appendingPathComponent("notch")
    }

    static func commandLineToolInstalled(home: URL = defaultHome) -> Bool {
        FileManager.default.isExecutableFile(atPath: commandLineToolURL(home: home).path)
    }

    static func installCommandLineTool(home: URL = defaultHome) throws {
        try writeScript(home: home)
        try writeCommandLineTool(home: home)
        guard let link = commandLineLinkURL(home: home) else { return }
        let fileManager = FileManager.default
        if let existing = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
            guard existing != commandLineToolURL(home: home).path else { return }
        }
        // Never replace someone else's `notch`.
        guard !fileManager.fileExists(atPath: link.path) else { return }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: commandLineToolURL(home: home))
    }

    static func uninstallCommandLineTool(home: URL = defaultHome) {
        let fileManager = FileManager.default
        if let link = commandLineLinkURL(home: home),
           (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == commandLineToolURL(home: home).path {
            try? fileManager.removeItem(at: link)
        }
        try? fileManager.removeItem(at: commandLineToolURL(home: home))
        let hooksUsed = CodingAgent.hookable.contains { [.installed, .partial].contains(status(for: $0, home: home)) }
        if !hooksUsed {
            try? fileManager.removeItem(at: scriptURL(home: home))
        }
    }

    private static func writeCommandLineTool(home: URL) throws {
        let url = commandLineToolURL(home: home)
        let contents = commandLineToolContents(hookPath: scriptURL(home: home).path)
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// `notch done|fail|ask [message]` and `notch run command…`, sent through `notch-hook`.
    static func commandLineToolContents(hookPath: String) -> String {
        """
        #!/bin/sh
        # Lights up the notch from any shell. Installed by Notch (Settings > Coding Agents).
        #   notch done "Tests passed"     notch fail "Deploy failed"     notch ask "Pick a name"
        #   notch run make test           runs the command, then reports how it went

        hook=\(shellQuoted(hookPath))

        usage() {
          echo "usage: notch done|fail|ask [message]" >&2
          echo "       notch run command [arguments...]" >&2
        }

        escape() {
          printf '%s' "$1" | sed -e 's/\\\\/\\\\\\\\/g' -e 's/"/\\\\"/g' | tr '\\t\\r\\n' '   '
        }

        send() {
          printf '{"hook_event_name":"Command","session_id":"cmd-%s-%s","cwd":"%s","status":"%s","message":"%s","command":"%s","duration":%s,"exit_code":%s}' \\
            "$$" "$(date +%s)" "$(escape "$PWD")" "$1" "$(escape "$2")" "$(escape "$3")" "${4:-0}" "${5:-0}" \\
            | "$hook" command
        }

        case "${1:-}" in
          done) shift; send done "$*" ;;
          fail) shift; send failed "$*" ;;
          ask) shift; send attention "$*" ;;
          run)
            shift
            if [ $# -eq 0 ]; then usage; exit 2; fi
            started=$(date +%s)
            "$@"
            code=$?
            if [ $code -eq 0 ]; then status=done; else status=failed; fi
            send "$status" "" "$*" "$(( $(date +%s) - started ))" "$code"
            exit $code
            ;;
          *) usage; exit 2 ;;
        esac

        """
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
        mode="${2:-}"
        if [ -z "$agent" ] && [ -n "${CURSOR_VERSION:-}" ]; then
          agent=cursor
        fi
        socket=\(shellQuoted(socketPath))
        if [ -z "$agent" ] || [ ! -S "$socket" ]; then
          cat >/dev/null
          exit 0
        fi
        tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')

        send() {
          /usr/bin/curl --silent --max-time "$1" \\
            --unix-socket "$socket" \\
            --header 'Content-Type: application/json' \\
            --header 'Expect:' \\
            --header "X-Notch-Host-Bundle: ${__CFBundleIdentifier:-}" \\
            --header "X-Notch-Term-Program: ${TERM_PROGRAM:-}" \\
            --header "X-Notch-Iterm-Session: ${ITERM_SESSION_ID:-}" \\
            --header "X-Notch-TTY: $tty" \\
            --data-binary @- \\
            "http://localhost/$2/$agent" 2>/dev/null
        }

        # --decide: wait for an Allow or Deny from the notch, then print it as the hook's answer.
        # Notch answers right away with nothing when it isn't going to ask.
        if [ "$mode" = "--decide" ]; then
          answer=$(send 50 decide)
          if [ -n "$answer" ]; then
            printf '%s\\n' "$answer"
          fi
        else
          send 2 agents >/dev/null
        fi
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
        case .command: AgentHookInstaller.directory(home: home)
        }
    }

    func hookConfigURL(home: URL = AgentHookInstaller.defaultHome) -> URL {
        switch self {
        case .claude: homeDirectory(home: home).appendingPathComponent("settings.json")
        case .cursor, .codex, .command: homeDirectory(home: home).appendingPathComponent("hooks.json")
        }
    }

    var hookConfigDisplayPath: String {
        switch self {
        case .claude: "~/.claude/settings.json"
        case .cursor: "~/.cursor/hooks.json"
        case .codex: "~/.codex/hooks.json"
        case .command: "~/.config/notch/notch"
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
        case .command:
            []
        }
    }

    /// Claude Code and Codex nest command hooks in matcher groups; Cursor lists them directly.
    var groupsHooks: Bool {
        self != .cursor
    }

    var emptyConfig: [String: Any] {
        switch self {
        case .cursor: ["version": 1, "hooks": [String: Any]()]
        case .claude, .codex, .command: ["hooks": [String: Any]()]
        }
    }

    /// Cursor gets no argument in case it runs the command without a shell; the script
    /// recognizes it by `CURSOR_VERSION`.
    func hookCommand(scriptPath: String) -> String {
        let script = AgentHookInstaller.shellQuoted(scriptPath)
        switch self {
        case .claude, .codex, .command: return "\(script) \(rawValue)"
        case .cursor: return script
        }
    }

    /// `async` keeps Claude Code and Codex from waiting on Notch. Permission requests are the
    /// exception: that hook runs in step so Notch can answer it, and it returns immediately
    /// unless answering from the notch is on.
    func hookEntry(event: String, scriptPath: String) -> [String: Any] {
        let command = hookCommand(scriptPath: scriptPath)
        switch self {
        case .claude, .codex, .command:
            if event == "PermissionRequest", acceptsDecisions {
                return ["type": "command", "command": command + " --decide", "timeout": AgentHookInstaller.decisionTimeout]
            }
            return ["type": "command", "command": command, "async": true, "timeout": AgentHookInstaller.timeout]
        case .cursor:
            return ["command": command, "timeout": AgentHookInstaller.timeout]
        }
    }
}
