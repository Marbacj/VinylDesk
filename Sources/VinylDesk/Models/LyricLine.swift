import Foundation

public struct LyricLine: Sendable, Equatable, Codable, Identifiable {
    public let time: TimeInterval
    public let text: String
    public var translation: String?

    public var id: String {
        "\(Int((time * 1000).rounded()))-\(text)"
    }

    public init(time: TimeInterval, text: String, translation: String? = nil) {
        self.time = time
        self.text = text
        self.translation = translation
    }
}

public struct CachedLyrics: Sendable, Codable {
    public let lines: [LyricLine]
    public let hasTranslation: Bool
    public let source: String
    public let fetchedAt: Date

    public init(lines: [LyricLine], hasTranslation: Bool, source: String, fetchedAt: Date = Date()) {
        self.lines = lines
        self.hasTranslation = hasTranslation
        self.source = source
        self.fetchedAt = fetchedAt
    }
}
