import SwiftUI

extension CodingAgent {
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .cursor: Color.white.opacity(0.92)
        case .codex: Color(red: 0.48, green: 0.72, blue: 1.0)
        case .command: Color.white.opacity(0.85)
        }
    }
}

extension AgentSessionState {
    var tint: Color {
        switch self {
        case .attention: Color(red: 1.0, green: 0.62, blue: 0.04)
        case .finished: Color(red: 0.32, green: 0.84, blue: 0.39)
        case .failed: Color(red: 1.0, green: 0.27, blue: 0.23)
        case .info, .working: Color.white.opacity(0.7)
        }
    }

    /// A turn that ends on a question is the user's move, whether or not the agent keeps it open.
    func tint(question: Bool) -> Color {
        question ? Color(red: 0.39, green: 0.7, blue: 1.0) : tint
    }
}

/// Pulses a view while an agent waits on the user.
struct AttentionPulse: ViewModifier {
    var active: Bool

    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.35 : 1)
            .animation(active ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: dimmed)
            .onAppear { dimmed = active }
            .onChange(of: active) { _, isActive in dimmed = isActive }
    }
}

/// Agent sessions that wait on the user, are working, finished, or failed, in the expanded notch.
struct AgentInboxView: View {
    var sideInset: CGFloat
    /// Keeps rows below the stage buttons and the camera housing.
    var topInset: CGFloat

    @Environment(AgentActivityCenter.self) private var agents
    @Environment(NotchHost.self) private var host

    private let maxRows = 3

    var body: some View {
        let inbox = agents.inbox
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(inbox.prefix(maxRows)) { session in
                    AgentRow(
                        session: session,
                        now: context.date,
                        open: { host.openAgentSession(session) },
                        dismiss: { agents.dismiss(session.id) },
                        answer: { agents.answer(session.id, allow: $0) },
                        reply: { agents.reply(session.id, text: $0) }
                    )
                }
                if inbox.count > maxRows {
                    HStack {
                        Text("\(inbox.count - maxRows) more")
                        Spacer()
                        Button("Clear All") { agents.clearAll() }
                            .buttonStyle(.plain)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, sideInset)
            .padding(.top, topInset + 6)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct AgentRow: View {
    let session: AgentSession
    let now: Date
    var open: () -> Void
    var dismiss: () -> Void
    var answer: (Bool) -> Void
    var reply: (String) -> Void

    @State private var isReplying = false
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    private var canReply: Bool {
        session.acceptsReplies && session.state == .attention && !session.awaitsDecision
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: session.agent.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(session.agent.tint)
                        .frame(width: 26, height: 26)
                        .background(session.agent.tint.opacity(0.16), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.headline)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.94))
                                .lineLimit(1)
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(session.state.tint(question: session.isQuestion))
                                .lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            if !session.awaitsDecision {
                                Text(Self.age(of: session.updatedAt, now: now))
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        if !isReplying, let detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Show \(session.agent.shortTitle)")
            .overlay(alignment: .bottomLeading) {
                if isReplying {
                    TextField("Reply to \(session.agent.shortTitle)", text: $replyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .focused($replyFocused)
                        .onSubmit(sendReply)
                        .onExitCommand { isReplying = false }
                        .padding(.leading, 36)
                        .frame(height: 16)
                }
            }

            if session.awaitsDecision {
                decisionButton("Deny", prominent: false) { answer(false) }
                decisionButton("Allow", prominent: true) { answer(true) }
            } else {
                if canReply {
                    iconButton(isReplying ? "paperplane.fill" : "arrowshape.turn.up.left.fill", help: "Reply") {
                        if isReplying {
                            sendReply()
                        } else {
                            isReplying = true
                            replyFocused = true
                        }
                    }
                }
                iconButton("xmark", help: "Dismiss", action: dismiss)
            }
        }
        .frame(height: 36)
    }

    private var title: String {
        session.state == .working ? "Working" : session.title
    }

    private var detail: String? {
        if session.state == .working, let started = session.turnStartedAt {
            let elapsed = Self.clock(now.timeIntervalSince(started))
            let tools = session.toolCount == 1 ? "1 tool" : "\(session.toolCount) tools"
            return "\(elapsed) · \(tools)"
        }
        if let resetsAt = session.resetsAt, resetsAt > now {
            return "Resets in \(AgentEvent.duration(Int(resetsAt.timeIntervalSince(now))))"
        }
        return session.detail
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply(text)
        replyText = ""
        isReplying = false
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func decisionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    prominent ? AgentSessionState.attention.tint : Color.white.opacity(0.14),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    /// “4:07”, “1:02:07”.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// The collapsed notch while an agent works and nothing else is showing.
struct AgentRunLine: View {
    let session: AgentSession
    var centerGap: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: session.agent.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(session.agent.tint)
                    .modifier(AttentionPulse(active: true))
                Text(session.agent.shortTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: max(8, centerGap))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentRow.clock(context.date.timeIntervalSince(session.turnStartedAt ?? context.date)))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
