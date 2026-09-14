import AppKit
import Foundation

@Observable
@MainActor
final class NowPlayingMonitor {
    private(set) var item: NowPlayingItem?
    private(set) var appIcon: NSImage?
    private(set) var artwork: NSImage?

    private var process: Process?
    private var stdout: Pipe?
    private var buffer = Data()
    private var restartWork: DispatchWorkItem?
    private var started = false
    private var iconCache: [String: NSImage] = [:]
    private var artworkTask: Task<Void, Never>?
    private var artworkKey: String?

    func start() {
        guard !started else { return }
        started = true
        spawnHelper()
    }

    func stop() {
        started = false
        restartWork?.cancel()
        restartWork = nil
        tearDownProcess()
        artworkTask?.cancel()
        artworkTask = nil
        artworkKey = nil
        item = nil
        appIcon = nil
        artwork = nil
    }

    func togglePlayPause() {
        if var current = item {
            current.isPlaying.toggle()
            item = current
        }
        MediaKeyControl.togglePlayPause()
    }

    func skipNext() {
        MediaKeyControl.skipNext()
    }

    func skipPrevious() {
        MediaKeyControl.skipPrevious()
    }

    private func icon(for item: NowPlayingItem) -> NSImage? {
        guard let bundleIdentifier = item.bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        if let cached = iconCache[bundleIdentifier] { return cached }
        let image: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleIdentifier }?
                .icon
        }
        if let image {
            iconCache[bundleIdentifier] = image
        }
        return image
    }

    private func spawnHelper() {
        tearDownProcess()
        guard started else { return }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let stdin = Pipe()
        process.standardInput = stdin

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in
                self?.consume(chunk)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination()
            }
        }

        do {
            try process.run()
            if let data = Self.helperScript.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            stdin.fileHandleForWriting.closeFile()
            self.process = process
            self.stdout = pipe
        } catch {
            NSLog("Notch: now playing helper failed to start: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func consume(_ chunk: Data) {
        if chunk.isEmpty { return }
        buffer.append(chunk)
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            apply(line: line)
        }
    }

    private func apply(line: Data) {
        guard let lineString = String(data: line, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !lineString.isEmpty
        else { return }
        if lineString == "null" {
            item = nil
            appIcon = nil
            clearArtwork()
            return
        }
        guard let data = lineString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(HelperPayload.self, from: data)
        else { return }
        let next = payload.item
        item = next
        appIcon = next.flatMap { icon(for: $0) }
        refreshArtwork(for: next)
    }

    private func refreshArtwork(for next: NowPlayingItem?) {
        guard let next else {
            clearArtwork()
            return
        }
        let key = next.artworkKey
        if key == artworkKey { return }
        artworkTask?.cancel()
        artworkKey = key
        artwork = nil
        let requested = next
        artworkTask = Task { [weak self] in
            let image = await NowPlayingArtwork.resolve(for: requested)
            guard !Task.isCancelled else { return }
            self?.applyArtwork(image, key: key)
        }
    }

    private func applyArtwork(_ image: NSImage?, key: String) {
        guard artworkKey == key else { return }
        artwork = image
    }

    private func clearArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkKey = nil
        artwork = nil
    }

    private func handleTermination() {
        tearDownProcess()
        guard started else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.spawnHelper()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func tearDownProcess() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        stdout = nil
        buffer.removeAll()
    }

    private struct HelperPayload: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var bundleIdentifier: String?
        var appName: String?
        var isPlaying: Bool?

        var item: NowPlayingItem? {
            let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty || !artist.isEmpty else { return nil }
            return NowPlayingItem(
                title: title,
                artist: artist,
                album: album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                isPlaying: isPlaying ?? false
            )
        }
    }

    /// Reads the same Now Playing registry Control Center uses, via osascript
    /// (Apple-signed, so MediaRemote still works on macOS 15.4+).
    private static let helperScript = """
    ObjC.import('Foundation');

    const MediaRemote = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    if (!MediaRemote.load) { MediaRemote.loadAndReturnError(null); }

    const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
    let last = '';

    function unwrap(value) {
      if (value === undefined || value === null) return null;
      try {
        const js = ObjC.unwrap(value);
        if (js === undefined || js === null) return null;
        return js;
      } catch (e) {
        return null;
      }
    }

    function snapshot() {
      const Request = $.NSClassFromString('MRNowPlayingRequest');
      if (!Request) return null;
      const item = Request.localNowPlayingItem;
      const info = item ? item.nowPlayingInfo : null;
      if (!info) return null;
      function str(key) {
        const value = unwrap(info.valueForKey(key));
        return value === null ? '' : String(value);
      }
      function num(key) {
        const value = unwrap(info.valueForKey(key));
        if (value === null || value === undefined || value === '') return null;
        const number = Number(value);
        return isNaN(number) ? null : number;
      }
      const path = Request.localNowPlayingPlayerPath;
      const client = path ? path.client : null;
      const rate = num('kMRMediaRemoteNowPlayingInfoPlaybackRate');
      return {
        title: str('kMRMediaRemoteNowPlayingInfoTitle'),
        artist: str('kMRMediaRemoteNowPlayingInfoArtist'),
        album: str('kMRMediaRemoteNowPlayingInfoAlbum'),
        bundleIdentifier: client ? (unwrap(client.bundleIdentifier) || null) : null,
        appName: client ? (unwrap(client.displayName) || null) : null,
        isPlaying: rate === null ? false : rate > 0
      };
    }

    function emit(payload) {
      const line = JSON.stringify(payload);
      if (line === last) return;
      last = line;
      const data = $(line + '\\n').dataUsingEncoding($.NSUTF8StringEncoding);
      stdout.writeData(data);
    }

    while (true) {
      try {
        const current = snapshot();
        emit(current === null ? {} : current);
      } catch (e) {
        emit({});
      }
      delay(0.7);
    }
    """
}
