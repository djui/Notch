import SwiftUI

extension CodingAgent {
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .cursor: Color.white.opacity(0.92)
        case .codex: Color(red: 0.48, green: 0.72, blue: 1.0)
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

/// Agent sessions that wait on the user, finished, or failed, in the expanded notch.
struct AgentInboxView: View {
    var sideInset: CGFloat
    /// Keeps rows out from under the camera housing.
    var topInset: CGFloat

    @Environment(AgentActivityCenter.self) private var agents
    @Environment(NotchHost.self) private var host

    private var maxRows: Int { topInset > 0 ? 2 : 3 }

    var body: some View {
        let inbox = agents.inbox
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(inbox.prefix(maxRows)) { session in
                    AgentRow(
                        session: session,
                        now: context.date,
                        open: { host.openAgentSession(session) },
                        dismiss: { agents.dismiss(session.id) }
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
            .padding(.top, topInset + 10)
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
                            Text(session.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(session.state.tint(question: session.isQuestion))
                                .lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(Self.age(of: session.updatedAt, now: now))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        if let detail = session.detail {
                            Text(detail)
                                .font(.system(size: 11))
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

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .frame(height: 36)
    }

    private static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
