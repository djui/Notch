import Foundation

@MainActor
enum MediaKeyControl {
    static func togglePlayPause() { send(2) }
    static func skipNext() { send(4) }
    static func skipPrevious() { send(5) }

    private static func send(_ command: Int) {
        if MediaRemoteBridge.dylibURL != nil {
            DispatchQueue.global(qos: .userInitiated).async {
                MediaRemoteBridge.sendCommand(command)
            }
            return
        }
        sendViaAppleScript(command)
    }

    private static func sendViaAppleScript(_ command: Int) {
        guard let bundleID = AppModel.shared.nowPlaying.item?.bundleIdentifier,
              !bundleID.isEmpty
        else { return }
        let verb: String
        switch command {
        case 4: verb = "next track"
        case 5: verb = "previous track"
        default: verb = "playpause"
        }
        let escaped = bundleID.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application id "\(escaped)"
            try
                \(verb)
            end try
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
