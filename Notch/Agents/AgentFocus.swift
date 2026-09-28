import AppKit

/// Brings the user to an agent session: the exact iTerm2 or Terminal tab when the hook reported
/// one, otherwise the terminal or IDE window whose title names the project.
@MainActor
enum AgentFocus {
    static func reveal(_ session: AgentSession) {
        Task { @MainActor in
            await revealHost(of: session)
        }
    }

    /// Types a reply into the session's iTerm2 session or Terminal tab and presses Return.
    static func reply(_ text: String, to session: AgentSession) {
        Task { @MainActor in
            if let id = session.host.itermSessionID {
                _ = await runAppleScript(iTermReplyScript, arguments: [id, text])
            } else if let tty = session.host.tty {
                _ = await runAppleScript(terminalReplyScript, arguments: [tty, text])
            }
        }
    }

    private static func revealHost(of session: AgentSession) async {
        let host = session.host
        guard let bundleID = host.bundleIdentifier
            ?? bundleIdentifier(forTermProgram: host.termProgram)
            ?? session.agent.appBundleIdentifier
        else { return }

        if bundleID == iTermBundleID, let id = host.itermSessionID,
           await runAppleScript(iTermScript, argument: id) {
            return
        }
        if bundleID == terminalBundleID, let tty = host.tty,
           await runAppleScript(terminalScript, argument: tty) {
            return
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated })
        else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        NSApp.yieldActivation(to: app)
        if app.isHidden {
            _ = app.unhide()
        }
        _ = app.activate()

        guard let project = session.project?.lowercased(), !project.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(150))
        WindowRaiser.raiseWindow(of: app, minimumScore: 1, fallbackToFirst: false) { title in
            title.contains(project) ? 1 : 0
        }
    }

    private static let iTermBundleID = "com.googlecode.iterm2"
    private static let terminalBundleID = "com.apple.Terminal"

    /// For hooks that ran without `__CFBundleIdentifier`, such as inside tmux.
    private static func bundleIdentifier(forTermProgram program: String?) -> String? {
        switch program {
        case "iTerm.app": iTermBundleID
        case "Apple_Terminal": terminalBundleID
        case "ghostty": "com.mitchellh.ghostty"
        case "WezTerm": "com.github.wez.wezterm"
        case "WarpTerminal": "dev.warp.Warp-Stable"
        default: nil
        }
    }

    /// The session ID arrives as an argument, never inside the script source.
    private static let iTermScript = [
        "on run argv",
        "set target to item 1 of argv",
        "tell application id \"com.googlecode.iterm2\"",
        "repeat with w in windows",
        "repeat with t in tabs of w",
        "repeat with s in sessions of t",
        "if unique id of s is target then",
        "select w",
        "select t",
        "select s",
        "activate",
        "return \"ok\"",
        "end if",
        "end repeat",
        "end repeat",
        "end repeat",
        "end tell",
        "return \"missing\"",
        "end run",
    ]

    private static let terminalScript = [
        "on run argv",
        "set target to \"/dev/\" & item 1 of argv",
        "tell application id \"com.apple.Terminal\"",
        "repeat with w in windows",
        "repeat with t in tabs of w",
        "if tty of t is target then",
        "set selected tab of w to t",
        "set index of w to 1",
        "activate",
        "return \"ok\"",
        "end if",
        "end repeat",
        "end repeat",
        "end tell",
        "return \"missing\"",
        "end run",
    ]

    private static let iTermReplyScript = [
        "on run argv",
        "set target to item 1 of argv",
        "tell application id \"com.googlecode.iterm2\"",
        "repeat with w in windows",
        "repeat with t in tabs of w",
        "repeat with s in sessions of t",
        "if unique id of s is target then",
        "tell s to write text (item 2 of argv)",
        "return \"ok\"",
        "end if",
        "end repeat",
        "end repeat",
        "end repeat",
        "end tell",
        "return \"missing\"",
        "end run",
    ]

    /// `do script` in a tab types the text and presses Return in that tab's shell or program.
    private static let terminalReplyScript = [
        "on run argv",
        "set target to \"/dev/\" & item 1 of argv",
        "tell application id \"com.apple.Terminal\"",
        "repeat with w in windows",
        "repeat with t in tabs of w",
        "if tty of t is target then",
        "do script (item 2 of argv) in t",
        "return \"ok\"",
        "end if",
        "end repeat",
        "end repeat",
        "end tell",
        "return \"missing\"",
        "end run",
    ]

    /// True when the script printed "ok". The timeout leaves room to answer the Automation
    /// prompt the first time.
    private static func runAppleScript(_ lines: [String], argument: String) async -> Bool {
        await runAppleScript(lines, arguments: [argument])
    }

    private static func runAppleScript(_ lines: [String], arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = lines.flatMap { ["-e", $0] } + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 && text == "ok")
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
