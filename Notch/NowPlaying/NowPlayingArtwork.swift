import AppKit
import Foundation

@MainActor
enum NowPlayingArtwork {
    private static let cache = NSCache<NSString, NSImage>()
    private static var deniedAutomation = Set<String>()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "en",
        ]
        return URLSession(configuration: config)
    }()
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func resolve(for item: NowPlayingItem) async -> NSImage? {
        let key = item.artworkKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if item.isSpotifyApp, let image = await spotifyAppArtwork() {
            cache.setObject(image, forKey: key)
            return image
        }

        if item.isWebSource, let web = await webArtwork(for: item) {
            cache.setObject(web, forKey: key)
            return web
        }

        let delays: [UInt64] = [0, 500, 1_200]
        for (index, delay) in delays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return nil }
            }
            if let image = await mediaRemoteArtwork() {
                cache.setObject(image, forKey: key)
                return image
            }
            if index == 0, item.isSpotifyApp, let image = await spotifyAppArtwork() {
                cache.setObject(image, forKey: key)
                return image
            }
        }
        return nil
    }

    private static func spotifyAppArtwork() async -> NSImage? {
        let url = await Task.detached(priority: .utility) {
            SpotifyArtworkLookup.artworkURL()
        }.value
        guard let url else { return nil }
        return await image(from: url)
    }

    private static func mediaRemoteArtwork() async -> NSImage? {
        let data = await Task.detached(priority: .utility) {
            MediaRemoteBridge.artworkData()
        }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        return image
    }

    private static func webArtwork(for item: NowPlayingItem) async -> NSImage? {
        guard let url = await mediaTabURL(for: item) else { return nil }
        if let videoID = youtubeVideoID(from: url) {
            let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") ?? url
            return await youtubeArtwork(videoID: videoID, pageURL: watchURL)
        }
        if isSpotifyURL(url) {
            return await spotifyOEmbedArtwork(url)
        }
        return nil
    }

    private static func youtubeArtwork(videoID: String, pageURL: URL) async -> NSImage? {
        if let oembed = await youtubeOEmbed(pageURL) {
            if let author = oembed.authorURL.flatMap(URL.init(string:)),
               let avatar = await channelAvatar(from: author)
            {
                return avatar
            }
            if let thumb = oembed.thumbnailURL.flatMap(URL.init(string:)),
               let image = await image(from: thumb)
            {
                return image
            }
        }
        let thumbs = [
            URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"),
            URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"),
        ]
        for thumb in thumbs.compactMap({ $0 }) {
            if let image = await image(from: thumb) { return image }
        }
        return nil
    }

    private static func channelAvatar(from authorURL: URL) async -> NSImage? {
        guard let html = await text(from: authorURL, limit: 512_000) else { return nil }
        guard let imageURL = ogImageURL(in: html), isLikelyChannelAvatar(imageURL) else { return nil }
        return await image(from: imageURL)
    }

    private static func spotifyOEmbedArtwork(_ url: URL) async -> NSImage? {
        guard var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let oembedURL = components.url,
              let payload: OEmbed = await json(from: oembedURL),
              let thumb = payload.thumbnailURL.flatMap(URL.init(string:))
        else { return nil }
        return await image(from: thumb)
    }

    private static func youtubeOEmbed(_ pageURL: URL) async -> OEmbed? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: pageURL.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return nil }
        return await json(from: url)
    }

    private static func mediaTabURL(for item: NowPlayingItem) async -> URL? {
        guard let bundleID = item.bundleIdentifier, !bundleID.isEmpty else { return nil }
        if deniedAutomation.contains(bundleID) { return nil }
        let tabs = await Task.detached(priority: .utility) {
            BrowserTabLookup.tabs(bundleID: bundleID)
        }.value
        switch tabs {
        case .denied:
            deniedAutomation.insert(bundleID)
            return nil
        case .failed:
            return nil
        case .ok(let found):
            return pickMediaURL(from: found, item: item)
        }
    }

    private static func pickMediaURL(from tabs: [BrowserTab], item: NowPlayingItem) -> URL? {
        let relevant = tabs.filter { isYouTubeURL($0.url) || isSpotifyURL($0.url) }
        guard !relevant.isEmpty else { return nil }
        let title = item.displayTitle.lowercased()
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scored = relevant.map { tab -> (BrowserTab, Int) in
            let tabTitle = tab.title.lowercased()
            var score = 0
            if !title.isEmpty, tabTitle.contains(title) { score += 10 }
            if !artist.isEmpty, tabTitle.contains(artist) { score += 3 }
            if isYouTubeURL(tab.url) { score += 1 }
            return (tab, score)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 10 {
            return best.0.url
        }
        if relevant.count == 1 {
            return relevant[0].url
        }
        return nil
    }

    private static func json<T: Decodable>(from url: URL) async -> T? {
        guard let data = await data(from: url, limit: 256_000) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func text(from url: URL, limit: Int) async -> String? {
        guard let data = await data(from: url, limit: limit) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func image(from url: URL) async -> NSImage? {
        guard let data = await data(from: url, limit: 2_000_000) else { return nil }
        return NSImage(data: data)
    }

    private static func data(from url: URL, limit: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode),
                  data.count > 16
            else { return nil }
            if data.count > limit {
                return Data(data.prefix(limit))
            }
            return data
        } catch {
            return nil
        }
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        if host.contains("youtu.be") {
            let id = path.split(separator: "/").first.map(String.init)
            return isVideoID(id) ? id : nil
        }
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let id = items.first(where: { $0.name == "v" })?.value,
               isVideoID(id)
            {
                return id
            }
            let parts = path.split(separator: "/").map(String.init)
            if let marker = parts.firstIndex(where: { ["embed", "shorts", "live", "v"].contains($0) }),
               marker + 1 < parts.count,
               isVideoID(parts[marker + 1])
            {
                return parts[marker + 1]
            }
        }
        return nil
    }

    private static func isVideoID(_ value: String?) -> Bool {
        guard let value, value.count == 11 else { return false }
        return value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private static func isSpotifyURL(_ url: URL) -> Bool {
        (url.host?.lowercased() ?? "").contains("open.spotify.com")
    }

    private static func isLikelyChannelAvatar(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("yt3.") || host.contains("googleusercontent.com")
    }

    private static func ogImageURL(in html: String) -> URL? {
        let patterns = [
            #"property=["']og:image["'][^>]*content=["']([^"']+)["']"#,
            #"content=["']([^"']+)["'][^>]*property=["']og:image["']"#,
            #"property=["']og:image:url["'][^>]*content=["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html)
            {
                let raw = String(html[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&#x2F;", with: "/")
                if let url = URL(string: raw) { return url }
            }
        }
        return nil
    }

    private struct OEmbed: Decodable {
        var authorURL: String?
        var thumbnailURL: String?

        enum CodingKeys: String, CodingKey {
            case authorURL = "author_url"
            case thumbnailURL = "thumbnail_url"
        }
    }
}

private struct BrowserTab: Sendable {
    var title: String
    var url: URL
}

private enum TabLookup: Sendable {
    case ok([BrowserTab])
    case denied
    case failed
}

private enum BrowserTabLookup {
    static func tabs(bundleID: String) -> TabLookup {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", tabScript, bundleID]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failed
        }
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return .failed
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if err.localizedCaseInsensitiveContains("not authorized")
            || err.contains("-1743")
            || err.localizedCaseInsensitiveContains("not allowed")
        {
            return .denied
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let payload = try? JSONDecoder().decode(TabPayload.self, from: data) else { return .failed }
        return .ok(payload.tabs.compactMap { tab in
            guard let url = URL(string: tab.url), !tab.url.isEmpty else { return nil }
            return BrowserTab(title: tab.title, url: url)
        })
    }

    private struct TabPayload: Decodable {
        var tabs: [TabDTO]
    }

    private struct TabDTO: Decodable {
        var title: String
        var url: String
    }

    private static let tabScript = """
    function run(argv) {
      const bundleID = argv[0];
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
            if (url && /youtube\\.com|youtu\\.be|open\\.spotify\\.com|music\\.youtube\\.com/i.test(url)) {
              payload.tabs.push({ title: title, url: url });
            }
          }
        }
      } catch (e) {
        payload.error = String(e);
      }
      return JSON.stringify(payload);
    }
    """
}

private enum SpotifyArtworkLookup {
    static func artworkURL() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application id \"com.spotify.client\"",
            "-e", "if player state is stopped then return \"\"",
            "-e", "artwork url of current track",
            "-e", "end tell",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let raw = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            ?? ""
        guard !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        if scheme == "https" { return url }
        if scheme == "http" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            return components?.url
        }
        return nil
    }
}


