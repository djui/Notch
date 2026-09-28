import AppKit
import Foundation

enum AgentSessionState: Equatable, Sendable {
    case working
    case attention
    case finished
    case failed
    case info
}

/// The latest thing one agent session reported. `working` sessions stay out of the inbox.
struct AgentSession: Identifiable, Equatable {
    /// `AgentEvent.sessionKey`.
    let id: String
    var agent: CodingAgent
    var project: String?
    var state: AgentSessionState
    var title: String
    var detail: String?
    var isQuestion = false
    var updatedAt: Date
    var host: AgentHost
    var toolUseID: String?
    /// Opened, dismissed, or its banner timed out. Keeps the banner from coming back.
    var acknowledged = false

    var headline: String {
        guard let project else { return agent.shortTitle }
        return "\(agent.shortTitle) · \(project)"
    }
}

struct AgentLiveActivity: Equatable {
    var sessionKey: String
    var agent: CodingAgent
    var state: AgentSessionState
    var isQuestion: Bool
    var label: String

    init(_ session: AgentSession) {
        sessionKey = session.id
        agent = session.agent
        state = session.state
        isQuestion = session.isQuestion
        switch session.state {
        case _ where session.isQuestion:
            label = "Asks you"
        case .attention:
            label = "Needs you"
        case .finished:
            label = "Done"
        case .failed:
            label = "Failed"
        case .info, .working:
            label = session.title
        }
    }
}

/// Turns hook events from coding agents into notch banners, sounds, and an inbox.
@Observable
@MainActor
final class AgentActivityCenter {
    private(set) var sessions: [AgentSession] = []
    private(set) var isListening = false
    private(set) var serverError: String?

    @ObservationIgnored private var server: AgentHookServer?
    /// Detail that arrives before the event it belongs to, per session.
    @ObservationIgnored private var contexts: [String: AgentEvent] = [:]
    @ObservationIgnored private var started = false

    static let bannerDuration: TimeInterval = 6
    static let attentionBannerDuration: TimeInterval = 10 * 60
    private static let inboxLifetime: TimeInterval = 2 * 60 * 60
    private static let maxSessions = 24
    private static let testSessionID = "notch-test"

    /// Newest first, with sessions waiting on the user at the top.
    var inbox: [AgentSession] {
        let cutoff = Date().addingTimeInterval(-Self.inboxLifetime)
        return sessions
            .filter { $0.state != .working && ($0.updatedAt > cutoff || $0.state == .attention) }
            .sorted { lhs, rhs in
                let left = lhs.state == .attention ? 0 : 1
                let right = rhs.state == .attention ? 0 : 1
                if left != right { return left < right }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var needsAttention: Bool {
        sessions.contains { $0.state == .attention }
    }

    func start() {
        guard !started else { return }
        started = true
        AppModel.shared.liveActivity.onEnd = { [weak self] ended in
            self?.liveActivityDidEnd(ended)
        }
        AgentHookInstaller.refreshScript()
        applyPreferences()
    }

    func stop() {
        started = false
        stopServer()
    }

    func applyPreferences() {
        guard started else { return }
        if AppModel.shared.settings.showAgents {
            startServer()
        } else {
            stopServer()
            clearAll()
        }
    }

    // MARK: - Events

    func handle(_ request: AgentHookRequest) {
        guard AppModel.shared.settings.showAgents else { return }
        let name = request.path.split(separator: "/").last.map(String.init) ?? ""
        guard let agent = CodingAgent(rawValue: name),
              let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let event = AgentEvent.parse(agent: agent, payload: payload, host: AgentHost(headers: request.headers))
        else { return }
        apply(event)
    }

    func apply(_ incoming: AgentEvent) {
        var event = incoming
        let key = event.sessionKey
        var session = sessions.first { $0.id == key } ?? AgentSession(
            id: key,
            agent: event.agent,
            project: event.project,
            state: .working,
            title: event.title,
            updatedAt: event.date,
            host: event.host
        )
        session.host = event.host.merged(over: session.host)
        session.project = event.project ?? session.project

        switch event.kind {
        case .context:
            contexts[key] = event
            // The permission prompt can overtake the detail that belongs to it.
            if session.state == .attention, session.toolUseID == nil, let detail = event.detail,
               event.date.timeIntervalSince(session.updatedAt) < 5 {
                session.detail = detail
                session.toolUseID = event.toolUseID
            }
            store(session)
            return
        case .resumed:
            if session.state == .attention,
               event.toolUseID == nil || session.toolUseID == nil || event.toolUseID == session.toolUseID {
                session.state = .working
                store(session)
                withdrawBanner(for: key)
            } else {
                store(session)
            }
            return
        case .attention:
            // Claude repeats “waiting for your input” after a turn Notch already announced.
            if event.isIdleReminder, session.state != .working {
                return
            }
            if let context = contexts[key], event.date.timeIntervalSince(context.date) < 30 {
                event.detail = context.detail ?? event.detail
                event.toolUseID = event.toolUseID ?? context.toolUseID
            }
        case .finished:
            if event.message == nil {
                event.completeTurn(with: contexts[key]?.message)
            }
        case .info where session.state == .attention && !event.endsSession:
            // A subagent or compaction must not bury a request for the user.
            store(session)
            return
        case .failed, .info:
            break
        }
        contexts[key] = nil

        // A turn or session that ended no longer waits on the user, announced or not.
        let endsWait = event.kind == .finished || event.kind == .failed || event.endsSession
        if endsWait, session.state == .attention {
            session.state = .working
            store(session)
            withdrawBanner(for: key)
        }
        let isTest = event.sessionID == Self.testSessionID
        guard isTest || wantsAnnouncement(of: event.kind) else {
            if event.endsSession, session.state == .working {
                sessions.removeAll { $0.id == key }
            } else {
                store(session)
            }
            return
        }

        session.state = state(for: event.kind)
        session.title = event.title
        session.detail = event.detail
        session.isQuestion = event.isQuestion
        session.updatedAt = event.date
        session.toolUseID = event.toolUseID
        session.acknowledged = false
        store(session)
        announce(session, quietWhenHostInFront: !isTest)
    }

    // MARK: - User actions

    func acknowledge(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].acknowledged = true
        withdrawBanner(for: id)
    }

    func dismiss(_ id: String) {
        sessions.removeAll { $0.id == id }
        contexts[id] = nil
        withdrawBanner(for: id)
    }

    func clearAll() {
        let ids = sessions.map(\.id)
        sessions.removeAll()
        contexts.removeAll()
        for id in ids {
            withdrawBanner(for: id)
        }
    }

    /// Sends a sample permission prompt through the installed hook script when there is one,
    /// so the test covers the whole path, and clears it again after a few seconds.
    func sendTestNotification() {
        let payload: [String: Any] = [
            "hook_event_name": "Notification",
            "notification_type": "permission_prompt",
            "session_id": Self.testSessionID,
            "cwd": "Notch",
            "message": "This is a test from Notch Settings.",
        ]
        let script = AgentHookInstaller.scriptURL()
        if isListening,
           FileManager.default.isExecutableFile(atPath: script.path),
           let body = try? JSONSerialization.data(withJSONObject: payload) {
            Self.runHookScript(script, agent: .claude, body: body)
        } else if let event = AgentEvent.parse(agent: .claude, payload: payload) {
            apply(event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismiss("\(CodingAgent.claude.rawValue):\(Self.testSessionID)")
        }
    }

    // MARK: - Banners

    private func announce(_ session: AgentSession, quietWhenHostInFront: Bool) {
        let settings = AppModel.shared.settings
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hostInFront = session.host.bundleIdentifier != nil && session.host.bundleIdentifier == frontmost
        if session.state != .attention, quietWhenHostInFront, settings.agentQuietWhenFrontmost, hostInFront {
            return
        }
        AppModel.shared.liveActivity.present(
            .agent(AgentLiveActivity(session)),
            duration: session.state == .attention ? Self.attentionBannerDuration : Self.bannerDuration
        )
        if settings.agentSounds, let sound = Self.soundName(for: session.state) {
            NSSound(named: sound)?.play()
        }
        if session.state == .attention {
            Haptics.shared.tap()
        }
    }

    private func withdrawBanner(for id: String) {
        AppModel.shared.liveActivity.dismiss { activity in
            if case .agent(let agent) = activity {
                return agent.sessionKey == id
            }
            return false
        }
    }

    /// A timed-out attention banner stays in the inbox only. When any banner ends, bring back
    /// attention that a shorter banner covered up.
    private func liveActivityDidEnd(_ ended: LiveActivityKind) {
        if case .agent(let activity) = ended, activity.state == .attention,
           let index = sessions.firstIndex(where: { $0.id == activity.sessionKey }) {
            sessions[index].acknowledged = true
        }
        guard AppModel.shared.liveActivity.current == nil,
              let waiting = inbox.first(where: { $0.state == .attention && !$0.acknowledged })
        else { return }
        AppModel.shared.liveActivity.present(.agent(AgentLiveActivity(waiting)), duration: Self.attentionBannerDuration)
    }

    // MARK: - Helpers

    private func wantsAnnouncement(of kind: AgentEventKind) -> Bool {
        let settings = AppModel.shared.settings
        switch kind {
        case .attention: return settings.agentAttention
        case .finished: return settings.agentFinished
        case .failed: return settings.agentErrors
        case .info: return settings.agentOther
        case .resumed, .context: return false
        }
    }

    private func state(for kind: AgentEventKind) -> AgentSessionState {
        switch kind {
        case .attention: .attention
        case .finished: .finished
        case .failed: .failed
        case .info: .info
        case .resumed, .context: .working
        }
    }

    private static func soundName(for state: AgentSessionState) -> NSSound.Name? {
        switch state {
        case .attention: "Ping"
        case .finished: "Glass"
        case .failed: "Basso"
        case .info, .working: nil
        }
    }

    private func store(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if sessions[index] != session {
                sessions[index] = session
            }
        } else {
            sessions.insert(session, at: 0)
        }
        if sessions.count > Self.maxSessions,
           let oldest = sessions.indices.filter({ sessions[$0].state != .attention })
            .min(by: { sessions[$0].updatedAt < sessions[$1].updatedAt }) {
            let id = sessions[oldest].id
            sessions.remove(at: oldest)
            contexts[id] = nil
        }
    }

    private func startServer() {
        guard server == nil else { return }
        let server = AgentHookServer(socketPath: AgentHookInstaller.socketURL().path) { [weak self] request in
            Task { @MainActor in
                self?.handle(request)
            }
        }
        do {
            try server.start()
            self.server = server
            isListening = true
            serverError = nil
        } catch {
            isListening = false
            serverError = "Notch can't receive agent events: \(error.localizedDescription)"
            NSLog("Notch: agent hook server failed: \(error.localizedDescription)")
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        isListening = false
    }

    private static func runHookScript(_ script: URL, agent: CodingAgent, body: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, agent.rawValue]
        var environment = ProcessInfo.processInfo.environment
        // Otherwise the test would say Notch itself is the agent's host.
        environment.removeValue(forKey: "__CFBundleIdentifier")
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Notch: test hook failed to start: \(error.localizedDescription)")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            input.fileHandleForWriting.write(body)
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }
    }
}
