import Foundation

enum MediaRemoteBridge {
    static var dylibURL: URL? {
        Bundle.main.url(forResource: "libNotchMediaRemote", withExtension: "dylib")
    }

    static func sendCommand(_ command: Int) {
        _ = runHelper(
            symbol: "notch_send_media_command",
            extraEnvironment: ["NOTCH_MEDIA_COMMAND": String(command)],
            captureOutput: false
        )
    }

    static func artworkData() -> Data? {
        guard let output = runHelper(
            symbol: "notch_get_artwork",
            extraEnvironment: [:],
            captureOutput: true
        ) else { return nil }
        let trimmed = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            ?? ""
        guard !trimmed.isEmpty else { return nil }
        return Data(base64Encoded: trimmed)
    }

    @discardableResult
    private static func runHelper(
        symbol: String,
        extraEnvironment: [String: String],
        captureOutput: Bool
    ) -> Data? {
        guard let dylib = dylibURL else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", perlLoader, dylib.path]
        var environment = ProcessInfo.processInfo.environment
        environment["NOTCH_MEDIA_SYMBOL"] = symbol
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment
        let stdout = Pipe()
        process.standardOutput = captureOutput ? stdout : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Notch: MediaRemote helper failed: \(error.localizedDescription)")
            return nil
        }
        guard captureOutput else { return Data() }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    private static let perlLoader = """
    use strict;
    use DynaLoader;
    my $path = $ARGV[0];
    my $name = $ENV{NOTCH_MEDIA_SYMBOL} || "notch_send_media_command";
    my $handle = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
    my $symbol = DynaLoader::dl_find_symbol($handle, $name) or die "missing $name";
    DynaLoader::dl_install_xsub("main::notch_media", $symbol);
    notch_media();
    """
}
