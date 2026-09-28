import SwiftUI

/// The next meeting in the expanded notch, with a Join button when the event has a call link.
struct MeetingCardView: View {
    let meeting: Meeting
    var sideInset: CGFloat

    @Environment(LiveActivityCenter.self) private var liveActivity
    @Environment(NotchHost.self) private var host

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(meeting.calendarColor.map { Color(nsColor: $0) } ?? .red)
                    .frame(width: 4, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                    Text("\(timeRange) · \(meeting.countdown(at: context.date))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    if let url = meeting.joinURL {
                        Button {
                            host.collapse(restoreApp: false)
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text(meeting.joinServiceName.map { "Join \($0)" } ?? "Join")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .frame(height: 26)
                                .background(Color(red: 0.2, green: 0.84, blue: 0.29), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Calendar") {
                        host.collapse(restoreApp: false)
                        liveActivity.meetings.openInCalendar(meeting)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: meeting.start))–\(formatter.string(from: meeting.end))"
    }
}
