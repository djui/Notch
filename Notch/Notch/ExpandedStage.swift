/// What the expanded notch shows. When more than one has content, a row of buttons at the
/// top switches between them.
enum ExpandedStage: String, CaseIterable, Identifiable {
    case agents
    case meeting
    case nowPlaying
    case shelf

    var id: Self { self }

    var title: String {
        switch self {
        case .agents: "Coding Agents"
        case .meeting: "Next Meeting"
        case .nowPlaying: "Now Playing"
        case .shelf: "Shelf"
        }
    }

    var symbolName: String {
        switch self {
        case .agents: "bell.badge"
        case .meeting: "calendar"
        case .nowPlaying: "play.circle"
        case .shelf: "tray"
        }
    }
}
