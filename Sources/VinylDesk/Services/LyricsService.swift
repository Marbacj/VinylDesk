import CryptoKit
import Foundation

public actor LyricsService {
    private let cacheDirectory: URL
    private let session: URLSession
    private var memoryCache: [String: CachedLyrics] = [:]

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = caches.appendingPathComponent("VinylDesk/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
    }

    /// Multi-source lyrics resolution:
    /// 1. Local cache (memory -> disk)
    /// 2. Primary: LRCLIB (open-source synced lyrics)
    /// 3. Fallback / Bilingual enrichment: NetEase Cloud Music public lyrics (great for C-pop + translations)
    public func fetchLyrics(for track: TrackInfo, preferBilingual: Bool) async -> [LyricLine] {
        guard !track.isEmpty else { return [] }
        let key = cacheFilename(for: track)

        // Check memory cache first.
        if let cached = memoryCache[key] {
            if !preferBilingual || cached.hasTranslation || cached.source == "netease" {
                return cached.lines
            }
        }

        // Check disk cache.
        let fileURL = cacheDirectory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) {
            memoryCache[key] = cached
            if !preferBilingual || cached.hasTranslation || cached.source == "netease" {
                return cached.lines
            }
        }

        // Fetch from primary source (LRCLIB).
        let lrclibLines = await fetchFromLRCLIB(track: track)

        // If LRCLIB missed, OR user wants bilingual translation and LRCLIB has no translations, query fallback source.
        if lrclibLines.isEmpty {
            let netease = await fetchFromNetEase(track: track)
            if !netease.isEmpty {
                let hasTrans = netease.contains { $0.translation != nil }
                store(CachedLyrics(lines: netease, hasTranslation: hasTrans, source: "netease"), forKey: key)
                return netease
            }
            // Cache empty miss briefly in memory so we don't spam APIs if user pauses/resumes.
            memoryCache[key] = CachedLyrics(lines: [], hasTranslation: false, source: "none")
            return []
        }

        if preferBilingual {
            let netease = await fetchFromNetEase(track: track)
            let hasTrans = netease.contains { $0.translation != nil }
            if hasTrans {
                store(CachedLyrics(lines: netease, hasTranslation: true, source: "netease"), forKey: key)
                return netease
            }
        }

        store(CachedLyrics(lines: lrclibLines, hasTranslation: false, source: "lrclib"), forKey: key)
        return lrclibLines
    }

    private func store(_ lyrics: CachedLyrics, forKey key: String) {
        if memoryCache.count > 60 {
            memoryCache.removeAll()
        }
        memoryCache[key] = lyrics
        let fileURL = cacheDirectory.appendingPathComponent(key)
        if let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func cacheFilename(for track: TrackInfo) -> String {
        let digest = SHA256.hash(data: Data(track.cacheKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    // MARK: - Source 1: LRCLIB

    private func fetchFromLRCLIB(track: TrackInfo) async -> [LyricLine] {
        let cleanTitle = ArtworkService.cleanQueryTerm(track.title)
        let cleanArtist = ArtworkService.cleanQueryTerm(track.artist)

        // 1a. Exact endpoint
        if let exact = await lrclibGet(title: track.title, artist: track.artist, album: track.album, duration: track.duration) {
            return exact
        }

        // 1b. Search endpoint with cleaned title/artist
        if let searched = await lrclibSearch(title: cleanTitle, artist: cleanArtist, targetDuration: track.duration) {
            return searched
        }

        return []
    }

    private func lrclibGet(title: String, artist: String, album: String, duration: TimeInterval) async -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 1 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("VinylDesk/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let item = try JSONDecoder().decode(LRCLIBEntry.self, from: data)
            guard let synced = item.syncedLyrics, !synced.isEmpty else { return nil }
            let parsed = LRCParser.parse(lrc: synced)
            return parsed.isEmpty ? nil : parsed
        } catch {
            return nil
        }
    }

    private func lrclibSearch(title: String, artist: String, targetDuration: TimeInterval) async -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("VinylDesk/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let entries = try JSONDecoder().decode([LRCLIBEntry].self, from: data)
            let syncedEntries = entries.filter { !($0.syncedLyrics ?? "").isEmpty }
            guard !syncedEntries.isEmpty else { return nil }

            let best = syncedEntries.min { lhs, rhs in
                let dl = abs((lhs.duration ?? targetDuration) - targetDuration)
                let dr = abs((rhs.duration ?? targetDuration) - targetDuration)
                return dl < dr
            }

            if let best, let synced = best.syncedLyrics {
                if targetDuration > 5, let dur = best.duration, abs(dur - targetDuration) > 15 {
                    return nil
                }
                let parsed = LRCParser.parse(lrc: synced)
                return parsed.isEmpty ? nil : parsed
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Source 2: NetEase Cloud Music Fallback (C-Pop & Bilingual Translations)

    private func fetchFromNetEase(track: TrackInfo) async -> [LyricLine] {
        let cleanTitle = ArtworkService.cleanQueryTerm(track.title)
        let cleanArtist = ArtworkService.cleanQueryTerm(track.artist)
        let query = [cleanTitle, cleanArtist].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return [] }

        guard let songID = await searchNetEaseSongID(query: query, track: track) else {
            return []
        }

        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "tv", value: "1")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(NetEaseLyricResponse.self, from: data)
            guard let rawLRC = decoded.lrc?.lyric, !rawLRC.isEmpty else { return [] }
            let translationLRC = decoded.tlyric?.lyric
            return LRCParser.parse(lrc: rawLRC, translationLRC: translationLRC)
        } catch {
            return []
        }
    }

    private func searchNetEaseSongID(query: String, track: TrackInfo) async -> Int? {
        var components = URLComponents(string: "https://music.163.com/api/search/get/web")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
            guard let songs = decoded.result?.songs, !songs.isEmpty else { return nil }

            let targetTitle = ArtworkService.cleanQueryTerm(track.title).lowercased()
            let targetArtist = ArtworkService.cleanQueryTerm(track.artist).lowercased()

            let ranked = songs.max { lhs, rhs in
                netEaseScore(lhs, title: targetTitle, artist: targetArtist, duration: track.duration) <
                netEaseScore(rhs, title: targetTitle, artist: targetArtist, duration: track.duration)
            }
            guard let best = ranked,
                  netEaseScore(best, title: targetTitle, artist: targetArtist, duration: track.duration) >= 20 else {
                return nil
            }
            return best.id
        } catch {
            return nil
        }
    }

    private func netEaseScore(_ song: NetEaseSong, title: String, artist: String, duration: TimeInterval) -> Int {
        var score = 0
        let songName = song.name.lowercased()
        let artists = (song.artists ?? []).map { $0.name.lowercased() }.joined(separator: " ")

        if songName == title { score += 50 }
        else if songName.contains(title) || title.contains(songName) { score += 25 }

        if !artist.isEmpty {
            if artists.contains(artist) || artist.contains(artists) { score += 35 }
        }

        if duration > 5, let durMs = song.duration {
            let delta = abs(Double(durMs) / 1000.0 - duration)
            if delta <= 3 { score += 25 }
            else if delta <= 8 { score += 10 }
            else if delta > 20 { score -= 25 }
        }
        return score
    }
}

private struct LRCLIBEntry: Decodable {
    let syncedLyrics: String?
    let duration: Double?
}

private struct NetEaseSearchResponse: Decodable {
    let result: NetEaseSearchResult?
}

private struct NetEaseSearchResult: Decodable {
    let songs: [NetEaseSong]?
}

private struct NetEaseSong: Decodable {
    let id: Int
    let name: String
    let duration: Int?
    let artists: [NetEaseArtist]?
}

private struct NetEaseArtist: Decodable {
    let name: String
}

private struct NetEaseLyricResponse: Decodable {
    let lrc: NetEaseLyricContent?
    let tlyric: NetEaseLyricContent?
}

private struct NetEaseLyricContent: Decodable {
    let lyric: String?
}
