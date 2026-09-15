import Foundation

struct BrowserTab: Sendable {
    var title: String
    var url: URL?
    var windowIndex: Int
    var tabIndex: Int
}

enum TabLookup: Sendable {
    case ok([BrowserTab])
    case denied
    case failed
}

enum BrowserMediaTabs {
    private static let deniedLock = NSLock()
    private static var deniedBundleIDs = Set<String>()

    static func tabs(bundleID: String, mediaOnly: Bool) -> TabLookup {
        if isDenied(bundleID) { return .denied }
        let result = runJXA(listScript, arguments: [bundleID, mediaOnly ? "media" : "all"], timeout: 6)
        if result.denied {
            markDenied(bundleID)
            return .denied
        }
        guard !result.timedOut, let payload = try? JSONDecoder().decode(TabPayload.self, from: result.stdout) else {
            return .failed
        }
        return .ok(payload.tabs.map { tab in
            BrowserTab(
                title: tab.title,
                url: URL(string: tab.url),
                windowIndex: tab.windowIndex,
                tabIndex: tab.tabIndex
            )
        })
    }

    static func activateMatchingTab(bundleID: String, item: NowPlayingItem) -> Bool {
        switch tabs(bundleID: bundleID, mediaOnly: false) {
        case .denied, .failed:
            return false
        case .ok(let found):
            guard let best = bestMatch(in: found, item: item) else { return false }
            return activate(bundleID: bundleID, windowIndex: best.windowIndex, tabIndex: best.tabIndex)
        }
    }

    static func score(_ tab: BrowserTab, item: NowPlayingItem) -> Int {
        let tabTitle = tab.title.lowercased()
        let title = item.displayTitle.lowercased()
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var score = 0
        if !title.isEmpty, tabTitle.contains(title) { score += 10 }
        if !artist.isEmpty, tabTitle.contains(artist) { score += 3 }
        return score
    }

    private static func bestMatch(in tabs: [BrowserTab], item: NowPlayingItem) -> BrowserTab? {
        let scored = tabs.map { ($0, score($0, item: item)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 10 else { return nil }
        return best.0
    }

    private static func activate(bundleID: String, windowIndex: Int, tabIndex: Int) -> Bool {
        let result = runJXA(
            activateScript,
            arguments: [bundleID, String(windowIndex), String(tabIndex)],
            timeout: 6
        )
        if result.denied {
            markDenied(bundleID)
            return false
        }
        guard !result.timedOut,
              let payload = try? JSONDecoder().decode(ActivatePayload.self, from: result.stdout)
        else { return false }
        return payload.ok
    }

    private static func isDenied(_ bundleID: String) -> Bool {
        deniedLock.lock()
        defer { deniedLock.unlock() }
        return deniedBundleIDs.contains(bundleID)
    }

    private static func markDenied(_ bundleID: String) {
        deniedLock.lock()
        deniedBundleIDs.insert(bundleID)
        deniedLock.unlock()
    }

    private struct TabPayload: Decodable {
        var tabs: [TabDTO]
    }

    private struct TabDTO: Decodable {
        var title: String
        var url: String
        var windowIndex: Int
        var tabIndex: Int
    }

    private struct ActivatePayload: Decodable {
        var ok: Bool
    }

    private struct JXAResult {
        var stdout: Data
        var denied: Bool
        var timedOut: Bool
    }

    private static func runJXA(_ script: String, arguments: [String], timeout: TimeInterval) -> JXAResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return JXAResult(stdout: Data(), denied: false, timedOut: false)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return JXAResult(stdout: Data(), denied: false, timedOut: true)
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let denied = err.localizedCaseInsensitiveContains("not authorized")
            || err.contains("-1743")
            || err.localizedCaseInsensitiveContains("not allowed")
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return JXAResult(stdout: data, denied: denied, timedOut: false)
    }

    private static let listScript = """
    function run(argv) {
      const bundleID = argv[0];
      const mediaOnly = argv[1] === 'media';
      const payload = { tabs: [] };
      try {
        const app = Application(bundleID);
        const windows = app.windows();
        for (let i = 0; i < windows.length; i++) {
          const tabs = windows[i].tabs();
          for (let j = 0; j < tabs.length; j++) {
            let title = '';
            let url = '';
            try { title = String(tabs[j].title()); } catch (e) {
              try { title = String(tabs[j].name()); } catch (e2) {}
            }
            try { url = String(tabs[j].url()); } catch (e) {}
            if (mediaOnly && !(url && /youtube\\.com|youtu\\.be|open\\.spotify\\.com|music\\.youtube\\.com/i.test(url))) {
              continue;
            }
            if (!title && !url) continue;
            payload.tabs.push({ title: title, url: url, windowIndex: i, tabIndex: j });
          }
        }
      } catch (e) {
        payload.error = String(e);
      }
      return JSON.stringify(payload);
    }
    """

    private static let activateScript = """
    function run(argv) {
      const bundleID = argv[0];
      const windowIndex = Number(argv[1]);
      const tabIndex = Number(argv[2]);
      const payload = { ok: false };
      try {
        const app = Application(bundleID);
        const windows = app.windows();
        const window = windows[windowIndex];
        const tabs = window.tabs();
        const tab = tabs[tabIndex];
        try { app.reopen(); } catch (e) {}
        try { window.currentTab = tab; } catch (e) {}
        try { window.activeTabIndex = tabIndex + 1; } catch (e) {}
        try { window.activeTab = tab; } catch (e) {}
        try { window.index = 1; } catch (e) {}
        try { window.miniaturized = false; } catch (e) {}
        try { window.visible = true; } catch (e) {}
        app.activate();
        payload.ok = true;
      } catch (e) {
        payload.error = String(e);
      }
      return JSON.stringify(payload);
    }
    """
}
