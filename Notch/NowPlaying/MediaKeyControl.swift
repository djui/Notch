import Foundation

@MainActor
enum MediaKeyControl {
    static func togglePlayPause() { send(2) }
    static func skipNext() { send(4) }
    static func skipPrevious() { send(5) }

    private static func send(_ command: Int) {
        if sendViaEntitledHelper(command) { return }
        sendViaAppleScript(command)
    }

    /// Load a tiny dylib into `/usr/bin/perl`, which is still allowed to talk to MediaRemote.
    @discardableResult
    private static func sendViaEntitledHelper(_ command: Int) -> Bool {
        guard let dylib = Bundle.main.url(forResource: "libNotchMediaRemote", withExtension: "dylib") else {
            return false
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-e", perlLoader, dylib.path]
            var environment = ProcessInfo.processInfo.environment
            environment["NOTCH_MEDIA_COMMAND"] = String(command)
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("Notch: media command helper failed: \(error.localizedDescription)")
            }
        }
        return true
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

    private static let perlLoader = """
    use strict;
    use DynaLoader;
    my $path = $ARGV[0];
    my $handle = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
    my $symbol = DynaLoader::dl_find_symbol($handle, "notch_send_media_command")
        or die "missing notch_send_media_command";
    DynaLoader::dl_install_xsub("main::notch_send", $symbol);
    notch_send();
    """
}
