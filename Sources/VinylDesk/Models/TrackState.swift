import AppKit
import Foundation

public enum PlaybackStatus: String, Sendable, Equatable {
    case playing
    case paused
    case stopped
}

public struct TrackInfo: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = max(0, duration)
    }

    public var cacheKey: String {
        let raw = "\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(Int(duration.rounded()))"
        return raw
    }

    public var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
