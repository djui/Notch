import Foundation

/// Where an agent runs, read from the hook process environment by `notch-hook`.
struct AgentHost: Equatable, Sendable {
    /// `__CFBundleIdentifier` of the app that started the agent: a terminal, an IDE, or Claude.
    var bundleIdentifier: String?
    var termProgram: String?
    /// iTerm2 session UUID, the part after the colon in `ITERM_SESSION_ID`.
    var itermSessionID: String?
    /// Controlling terminal, such as `ttys003`.
    var tty: String?

    init(bundleIdentifier: String? = nil, termProgram: String? = nil, itermSessionID: String? = nil, tty: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.termProgram = termProgram
        self.itermSessionID = itermSessionID
        self.tty = tty
    }

    /// Header values come from another process, so keep only well-formed ones.
    init(headers: [String: String]) {
        bundleIdentifier = Self.matching(headers["x-notch-host-bundle"], #"^[A-Za-z0-9.\-]{1,200}$"#)
        termProgram = Self.matching(headers["x-notch-term-program"], #"^[A-Za-z0-9._\- ]{1,64}$"#)
        let iterm = headers["x-notch-iterm-session"]?.split(separator: ":").last.map(String.init)
        itermSessionID = Self.matching(iterm, #"^[A-Fa-f0-9\-]{8,64}$"#)
        tty = Self.matching(headers["x-notch-tty"], #"^ttys?[0-9]{1,4}$"#)
    }

    /// Keeps what earlier events reported when a later one arrives without it.
    func merged(over older: AgentHost) -> AgentHost {
        AgentHost(
            bundleIdentifier: bundleIdentifier ?? older.bundleIdentifier,
            termProgram: termProgram ?? older.termProgram,
            itermSessionID: itermSessionID ?? older.itermSessionID,
            tty: tty ?? older.tty
        )
    }

    private static func matching(_ raw: String?, _ pattern: String) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
              value.range(of: pattern, options: .regularExpression) != nil
        else { return nil }
        return value
    }
}

enum AgentEventKind: Equatable, Sendable {
    /// Blocked on the user: a permission prompt, a question, or idle input.
    case attention
    /// A turn finished.
    case finished
    /// A turn stopped on an error.
    case failed
    /// Session lifecycle worth announcing: start, end, compaction, subagents.
    case info
    /// The agent is working again. Clears earlier attention and is never shown.
    case resumed
    /// Detail for a later event, such as the command behind a permission prompt. Never shown.
    case context
}

/// One hook event from Claude Code, Cursor, or Codex, normalized across the three payload formats.
struct AgentEvent: Sendable {
    var agent: CodingAgent
    var kind: AgentEventKind
    /// Raw `hook_event_name`.
    var hookName: String
    var sessionID: String
    var title: String
    var detail: String?
    /// The assistant's last message, for finished turns and Cursor's `afterAgentResponse`.
    var message: String?
    var cwd: String?
    var toolUseID: String?
    /// A finished turn whose last line asks the user something.
    var isQuestion = false
    /// Claude's “waiting for your input” reminder, sent a while after a turn ends.
    var isIdleReminder = false
    var endsSession = false
    /// The user submitted a prompt; the agent is working from here.
    var startsTurn = false
    /// The agent is done working, whatever the outcome.
    var endsTurn = false
    var isToolUse = false
    /// When a rate limit lifts, if the failure said.
    var resetsAt: Date?
    var host = AgentHost()
    var date = Date()

    var sessionKey: String { "\(agent.rawValue):\(sessionID)" }

    /// The folder name, or the repository for agent worktrees such as
    /// `notch/.claude/worktrees/fix-bug` and `~/.cursor/worktrees/notch/abc`.
    var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let parts = URL(fileURLWithPath: cwd).pathComponents
        if let index = parts.lastIndex(of: "worktrees"), index >= 1 {
            switch parts[index - 1] {
            case ".claude" where index >= 2:
                return parts[index - 2]
            case ".cursor" where index + 1 < parts.count:
                return parts[index + 1]
            default:
                break
            }
        }
        guard let name = parts.last, name != "/" else { return nil }
        return name
    }

    /// Returns nil when the payload is not a hook event.
    static func parse(
        agent: CodingAgent,
        payload: [String: Any],
        host: AgentHost = AgentHost(),
        date: Date = Date()
    ) -> AgentEvent? {
        guard let name = payload.text("hook_event_name") else { return nil }
        var event = AgentEvent(
            agent: agent,
            kind: .info,
            hookName: name,
            sessionID: sessionID(agent: agent, payload: payload),
            title: humanized(name),
            cwd: workingDirectory(agent: agent, payload: payload),
            host: host,
            date: date
        )
        switch agent {
        case .claude: event.applyClaude(payload)
        case .codex: event.applyCodex(payload)
        case .cursor: event.applyCursor(payload)
        case .command: event.applyCommand(payload)
        }
        event.completeTurn(with: event.message)
        return event
    }

    /// Turns a finished turn that ends on a question into “Has a question”. Agents that report
    /// the next prompt keep it up as attention until the user answers.
    mutating func completeTurn(with message: String?) {
        guard kind == .finished, let message, let last = Self.lastLine(of: message) else { return }
        self.message = message
        if Self.isQuestion(last) {
            isQuestion = true
            title = "Has a question"
            detail = Self.oneLine(last)
            if agent.reportsResume {
                kind = .attention
            }
        } else {
            detail = Self.firstLine(of: message).map(Self.oneLine) ?? detail
        }
    }

    // MARK: - Per-agent payloads

    /// https://code.claude.com/docs/en/hooks
    private mutating func applyClaude(_ payload: [String: Any]) {
        switch Self.key(hookName) {
        case "notification":
            let message = payload.text("message")
            switch payload.text("notification_type") ?? "" {
            case "permission_prompt":
                set(.attention, "Needs permission", message)
            case "idle_prompt":
                set(.attention, "Waiting for you", message)
                isIdleReminder = true
            case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                set(.attention, "Needs input", message)
            case "elicitation_complete", "elicitation_response":
                kind = .resumed
            case "agent_completed":
                set(.finished, "Done", message)
            case "auth_success":
                set(.info, "Signed in", message)
            default:
                set(.info, "Notification", message)
            }
        case "permissionrequest":
            kind = .context
            detail = Self.toolSummary(name: payload.text("tool_name"), input: payload["tool_input"])
            toolUseID = payload.text("tool_use_id")
        case "stop":
            set(.finished, "Done", nil)
            message = payload.text("last_assistant_message")
            endsTurn = true
        case "stopfailure":
            set(.failed, "Failed", Self.failureReason(payload))
            endsTurn = true
            if detail == "Rate limited" {
                let now = date
                title = "Rate limited"
                resetsAt = Self.strings(in: payload).lazy.compactMap { Self.resetDate(in: $0, now: now) }.first
            }
        case "subagentstop":
            set(.info, "Subagent done", payload.text("agent_type"))
        case "sessionstart":
            set(.info, "Started", payload.text("source"))
        case "sessionend":
            set(.info, "Ended", payload.text("reason"))
            endsSession = true
        case "precompact":
            set(.info, "Compacting", payload.text("trigger"))
        case "userpromptsubmit", "pretooluse", "posttooluse", "posttoolusefailure", "posttoolbatch":
            kind = .resumed
            toolUseID = payload.text("tool_use_id")
            startsTurn = Self.key(hookName) == "userpromptsubmit"
            isToolUse = Self.key(hookName).hasPrefix("posttooluse")
        default:
            break
        }
    }

    /// https://developers.openai.com/codex/hooks
    private mutating func applyCodex(_ payload: [String: Any]) {
        switch Self.key(hookName) {
        case "permissionrequest":
            set(.attention, "Needs approval", Self.toolSummary(name: payload.text("tool_name"), input: payload["tool_input"]))
            toolUseID = payload.text("tool_use_id")
        case "stop":
            set(.finished, "Done", nil)
            message = payload.text("last_assistant_message")
            endsTurn = true
        case "subagentstop":
            set(.info, "Subagent done", payload.text("agent_type"))
        case "sessionstart":
            set(.info, "Started", payload.text("source"))
        case "sessionend":
            set(.info, "Ended", nil)
            endsSession = true
        case "precompact":
            set(.info, "Compacting", payload.text("trigger"))
        case "userpromptsubmit", "pretooluse", "posttooluse", "interrupt":
            kind = .resumed
            toolUseID = payload.text("tool_use_id")
            startsTurn = Self.key(hookName) == "userpromptsubmit"
            isToolUse = Self.key(hookName) == "posttooluse"
            endsTurn = Self.key(hookName) == "interrupt"
        default:
            break
        }
    }

    /// https://cursor.com/docs/hooks — Cursor has no hook for approval prompts.
    private mutating func applyCursor(_ payload: [String: Any]) {
        switch Self.key(hookName) {
        case "afteragentresponse":
            kind = .context
            message = payload.text("text")
        case "stop":
            endsTurn = true
            switch payload.text("status") {
            case "error":
                set(.failed, "Failed", nil)
            case "aborted":
                kind = .resumed
            default:
                set(.finished, "Done", nil)
            }
        case "subagentstop":
            set(.info, "Subagent done", payload.text("summary").map(Self.oneLine) ?? payload.text("subagent_type"))
        case "sessionstart":
            set(.info, "Started", payload.text("composer_mode"))
        case "sessionend":
            set(.info, "Ended", payload.text("reason"))
            endsSession = true
        case "precompact":
            set(.info, "Compacting", payload.text("trigger"))
        default:
            break
        }
    }

    /// `notch done|fail|ask` and `notch run` (see `AgentHookInstaller.commandScriptContents`).
    private mutating func applyCommand(_ payload: [String: Any]) {
        let command = payload.text("command")
        let seconds = (payload["duration"] as? NSNumber)?.intValue ?? 0
        let exitCode = (payload["exit_code"] as? NSNumber)?.intValue ?? 0
        var parts: [String] = []
        if let command { parts.append(command) }
        if seconds > 0 { parts.append(Self.duration(seconds)) }
        if exitCode != 0 { parts.append("exit \(exitCode)") }
        let summary = payload.text("message") ?? (parts.isEmpty ? nil : parts.joined(separator: " · "))
        switch payload.text("status") {
        case "failed": set(.failed, "Failed", summary)
        case "attention": set(.attention, "Needs you", summary)
        default: set(.finished, "Done", summary)
        }
        endsTurn = true
    }

    private mutating func set(_ kind: AgentEventKind, _ title: String, _ detail: String?) {
        self.kind = kind
        self.title = title
        self.detail = detail.map(Self.oneLine)
    }

    private static func sessionID(agent: CodingAgent, payload: [String: Any]) -> String {
        let id = agent == .cursor
            ? payload.text("conversation_id") ?? payload.text("session_id")
            : payload.text("session_id")
        return id ?? "default"
    }

    private static func workingDirectory(agent: CodingAgent, payload: [String: Any]) -> String? {
        if agent == .cursor, let roots = payload["workspace_roots"] as? [String], let first = roots.first, !first.isEmpty {
            return first
        }
        return payload.text("cwd")
    }

    // MARK: - Text

    /// “2m 3s”, “1h 5m”, “42s”.
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }

    /// Every string in a payload, for reset times that may appear in any field.
    static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let dict = value as? [String: Any] { return dict.values.flatMap(strings) }
        if let list = value as? [Any] { return list.flatMap(strings) }
        return []
    }

    /// Reads “resets 3pm”, “resets at 15:30”, or “try again in 1h 20m”.
    static func resetDate(in text: String, now: Date, calendar: Calendar = .current) -> Date? {
        let lower = text.lowercased()
        let clock = #"reset[s]?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let match = lower.firstMatch(of: try! Regex(clock)) {
            var hour = Int(match.output[1].substring ?? "") ?? 0
            let minute = match.output[2].substring.flatMap { Int($0) } ?? 0
            switch match.output[3].substring.map(String.init) {
            case "pm" where hour < 12: hour += 12
            case "am" where hour == 12: hour = 0
            default: break
            }
            guard hour < 24, minute < 60 else { return nil }
            let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
            return today.map { $0 > now ? $0 : calendar.date(byAdding: .day, value: 1, to: $0) ?? $0 }
        }
        let relative = #"in\s+(?:(\d+)\s*h(?:ours?)?)?\s*(?:(\d+)\s*m(?:in(?:utes?)?)?)?"#
        for match in lower.matches(of: try! Regex(relative)) {
            let hours = match.output[1].substring.flatMap { Int($0) } ?? 0
            let minutes = match.output[2].substring.flatMap { Int($0) } ?? 0
            if hours > 0 || minutes > 0 {
                return now.addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60))
            }
        }
        return nil
    }

    /// `PostToolUse`, `post_tool_use`, and `postToolUse` all become `posttooluse`.
    static func key(_ hookName: String) -> String {
        hookName.lowercased().replacingOccurrences(of: "_", with: "")
    }

    /// `TaskCompleted` and `task_completed` become “Task completed”.
    static func humanized(_ hookName: String) -> String {
        var words: [String] = []
        var current = ""
        for character in hookName {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ").lowercased()
        guard let first = sentence.first else { return "Event" }
        return first.uppercased() + sentence.dropFirst()
    }

    /// “Bash · git push”, “Edit · NotchHost.swift”.
    static func toolSummary(name: String?, input: Any?) -> String? {
        let tool = name.map(prettyToolName)
        let fields = input as? [String: Any]
        let subject = commandText(fields?["command"])
            ?? fields?.text("file_path").map(fileName)
            ?? fields?.text("notebook_path").map(fileName)
            ?? fields?.text("path").map(fileName)
            ?? fields?.text("url")
            ?? fields?.text("pattern")
            ?? fields?.text("description")
        switch (tool, subject) {
        case let (tool?, subject?): return oneLine("\(tool) · \(subject)")
        case let (tool?, nil): return tool
        case let (nil, subject?): return oneLine(subject)
        case (nil, nil): return nil
        }
    }

    /// Codex passes shell commands as `["bash", "-lc", "…"]`.
    private static func commandText(_ raw: Any?) -> String? {
        if let text = raw as? String {
            return nonEmpty(text)
        }
        guard let parts = raw as? [String], !parts.isEmpty else { return nil }
        if parts.count >= 3, ["-c", "-lc"].contains(parts[parts.count - 2]) {
            return nonEmpty(parts[parts.count - 1])
        }
        return nonEmpty(parts.joined(separator: " "))
    }

    /// `mcp__github__create_issue` becomes “github · create_issue”.
    private static func prettyToolName(_ name: String) -> String {
        let parts = name.components(separatedBy: "__")
        if parts.count >= 3, parts[0] == "mcp" {
            return "\(parts[1]) · \(parts[2...].joined(separator: "__"))"
        }
        return name
    }

    private static func fileName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func failureReason(_ payload: [String: Any]) -> String? {
        let raw = ["error_type", "reason", "error", "stop_reason", "failure_type"]
            .lazy.compactMap { payload.text($0) }.first
        guard let raw else { return payload.text("message") }
        switch raw {
        case "rate_limit": return "Rate limited"
        case "overloaded": return "API overloaded"
        case "authentication_failed": return "Authentication failed"
        case "billing_error": return "Billing error"
        case "server_error": return "Server error"
        case "max_output_tokens": return "Hit the output limit"
        case "model_not_found": return "Model not found"
        default: return humanized(raw)
        }
    }

    private static func isQuestion(_ line: String) -> Bool {
        line.trimmingCharacters(in: CharacterSet(charactersIn: " *_)]\"'”’")).hasSuffix("?")
    }

    static func firstLine(of text: String) -> String? {
        proseLines(text).first
    }

    static func lastLine(of text: String) -> String? {
        proseLines(text).last
    }

    /// Non-empty lines outside code fences, without list and heading markers.
    private static func proseLines(_ text: String) -> [String] {
        var inFence = false
        var lines: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            while let marker = line.range(of: #"^(#{1,6}|[-*+>]|[0-9]+[.)])\s+"#, options: .regularExpression) {
                line.removeSubrange(marker)
            }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    /// Collapses whitespace and caps the length for a one-line row.
    static func oneLine(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > 160 else { return collapsed }
        return collapsed.prefix(159).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

fileprivate extension Dictionary where Key == String, Value == Any {
    func text(_ key: String) -> String? {
        guard let value = self[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
