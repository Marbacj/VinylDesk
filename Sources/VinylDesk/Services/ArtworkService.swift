import AppKit
import CryptoKit
import Foundation

public actor ArtworkService {
    private let cacheDirectory: URL
    private let session: URLSession
    private var memoryCache: [String: Data] = [:]

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = caches.appendingPathComponent("VinylDesk/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
    }

    /// Resolves high-resolution artwork bytes: local Apple Music artwork -> disk cache -> iTunes Search API fallback.
    public func resolveArtworkData(for track: TrackInfo, localArtworkData: Data?) async -> Data? {
        let key = cacheFilename(for: track)

        // 1. Prefer fresh raw bytes directly from Apple Music if valid image data.
        if let localArtworkData, !localArtworkData.isEmpty, NSImage(data: localArtworkData) != nil {
            store(data: localArtworkData, forKey: key)
            return localArtworkData
        }

        // 2. Check memory cache.
        if let cached = memoryCache[key] {
            return cached
        }

        // 3. Check disk cache.
        let fileURL = cacheDirectory.appendingPathComponent(key)
        if let diskData = try? Data(contentsOf: fileURL), !diskData.isEmpty {
            memoryCache[key] = diskData
            return diskData
        }

        // 4. Fallback to public iTunes Search API (no API key required, upgrades to 600x600).
        if let remoteData = await fetchFromiTunesSearch(for: track) {
            store(data: remoteData, forKey: key)
            return remoteData
        }

        return nil
    }

    private func store(data: Data, forKey key: String) {
        if memoryCache.count > 40 {
            memoryCache.removeAll()
        }
        memoryCache[key] = data
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheFilename(for track: TrackInfo) -> String {
        let base = "\(track.artist.lowercased())|\(track.album.lowercased())|\(track.title.lowercased())"
        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    private func fetchFromiTunesSearch(for track: TrackInfo) async -> Data? {
        let cleanTitle = Self.cleanQueryTerm(track.title)
        let cleanArtist = Self.cleanQueryTerm(track.artist)
        let term = [cleanArtist, cleanTitle].filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let best = selectBestResult(from: decoded.results, track: track),
                  let artwork100 = best.artworkUrl100 else {
                return nil
            }

            let highResString = artwork100
                .replacingOccurrences(of: "100x100bb", with: "600x600bb")
                .replacingOccurrences(of: "100x100", with: "600x600")
            guard let imageURL = URL(string: highResString) else { return nil }

            let (imgData, imgResp) = try await session.data(from: imageURL)
            guard let imgHttp = imgResp as? HTTPURLResponse, imgHttp.statusCode == 200,
                  NSImage(data: imgData) != nil else {
                return nil
            }
            return imgData
        } catch {
            return nil
        }
    }

    private func selectBestResult(from results: [ITunesTrackResult], track: TrackInfo) -> ITunesTrackResult? {
        guard !results.isEmpty else { return nil }

        let targetTitle = Self.cleanQueryTerm(track.title).lowercased()
        let targetArtist = Self.cleanQueryTerm(track.artist).lowercased()
        let targetAlbum = Self.cleanQueryTerm(track.album).lowercased()

        return results.max { lhs, rhs in
            score(lhs, targetTitle: targetTitle, targetArtist: targetArtist, targetAlbum: targetAlbum) <
            score(rhs, targetTitle: targetTitle, targetArtist: targetArtist, targetAlbum: targetAlbum)
        }
    }

    private func score(
        _ item: ITunesTrackResult,
        targetTitle: String,
        targetArtist: String,
        targetAlbum: String
    ) -> Int {
        var points = 0
        let name = (item.trackName ?? "").lowercased()
        let artist = (item.artistName ?? "").lowercased()
        let album = (item.collectionName ?? "").lowercased()

        if name == targetTitle { points += 50 }
        else if name.contains(targetTitle) || targetTitle.contains(name) { points += 25 }

        if !targetArtist.isEmpty {
            if artist == targetArtist { points += 40 }
            else if artist.contains(targetArtist) || targetArtist.contains(artist) { points += 20 }
        }

        if !targetAlbum.isEmpty {
            if album == targetAlbum { points += 25 }
            else if album.contains(targetAlbum) || targetAlbum.contains(album) { points += 10 }
        }

        if item.artworkUrl100 != nil { points += 5 }
        return points
    }

    static func cleanQueryTerm(_ input: String) -> String {
        let stripped = input.replacingOccurrences(
            of: #"\s*[\(\[（【](?:feat\.?|ft\.?|remaster(?:ed)?|deluxe|live|explicit|version|radio edit|bonus track)[^\)\]）】]*[\)\]）】]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesTrackResult]
}

private struct ITunesTrackResult: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
}
