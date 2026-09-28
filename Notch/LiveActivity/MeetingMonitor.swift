import AppKit
import EventKit

struct Meeting: Equatable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var joinURL: URL?
    var calendarColor: NSColor?

    var joinServiceName: String? {
        guard let host = joinURL?.host?.lowercased() else { return nil }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Meet" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return nil
    }
}

/// The next timed event from the user's calendars. Announces it five minutes ahead.
@Observable
@MainActor
final class MeetingMonitor {
    /// Starts within the hour, or started less than ten minutes ago.
    private(set) var upcoming: Meeting?
    private(set) var accessDenied = false
    @ObservationIgnored var onSoon: ((Meeting) -> Void)?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    @ObservationIgnored private var announced: Set<String> = []

    static let leadTime: TimeInterval = 5 * 60

    func start() {
        stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await requestAccess() else {
                accessDenied = true
                return
            }
            accessDenied = false
            refresh()
            storeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: store,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        upcoming = nil
    }

    func openInCalendar(_ meeting: Meeting) {
        let id = meeting.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? meeting.id
        if let url = URL(string: "ical://ekevent/\(id)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    private func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60 * 60),
            end: now.addingTimeInterval(60 * 60),
            calendars: nil
        )
        let next = store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && event.status != .canceled
                    && event.startDate > now.addingTimeInterval(-10 * 60)
                    && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .min { $0.startDate < $1.startDate }
            .map(Self.meeting)
        if next != upcoming {
            upcoming = next
        }
        guard let next, !announced.contains(next.id) else { return }
        let lead = next.start.timeIntervalSince(now)
        if lead <= Self.leadTime, lead > -2 * 60 {
            announced.insert(next.id)
            onSoon?(next)
        }
    }

    private static func meeting(from event: EKEvent) -> Meeting {
        Meeting(
            id: event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString,
            title: event.title?.isEmpty == false ? event.title : "Untitled event",
            start: event.startDate,
            end: event.endDate,
            joinURL: joinURL(in: [event.url?.absoluteString, event.location, event.notes]),
            calendarColor: event.calendar.map { NSColor(cgColor: $0.cgColor) } ?? nil
        )
    }

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]

    /// The first video-call link in the event's URL, location, or notes.
    static func joinURL(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
