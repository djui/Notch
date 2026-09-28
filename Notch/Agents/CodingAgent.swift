import Foundation

/// Coding agents that report hook events to Notch.
enum CodingAgent: String, CaseIterable, Identifiable, Sendable {
    case claude
    case cursor
    case codex
    /// `notch done` and `notch run` from any shell.
    case command

    var id: Self { self }

    /// Agents with a hook config Notch can install into.
    static let hookable: [CodingAgent] = [.claude, .cursor, .codex]

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .command: "Command line"
        }
    }

    /// Fits the collapsed notch.
    var shortTitle: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .command: "Shell"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "asterisk"
        case .cursor: "cursorarrow.rays"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .command: "terminal"
        }
    }

    /// Whether the agent reports the user picking up again (a new prompt, an approved tool),
    /// so an attention banner can stay up until then. Cursor only reports finished runs.
    var reportsResume: Bool {
        self == .claude || self == .codex
    }

    /// Permission requests Notch can answer from the notch.
    var acceptsDecisions: Bool {
        self == .claude || self == .codex
    }

    /// The IDE that runs the agent itself. Terminal agents report their host app per event.
    var appBundleIdentifier: String? {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .claude, .codex, .command: nil
        }
    }
}
