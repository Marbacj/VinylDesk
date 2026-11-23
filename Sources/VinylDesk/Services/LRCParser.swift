import Foundation

public enum LRCParser {
    /// Parses synced LRC text into sorted `LyricLine` items, optionally merging a translation LRC.
    public static func parse(lrc: String, translationLRC: String? = nil) -> [LyricLine] {
        var primary = parseSingle(lrc)
        guard !primary.isEmpty else { return [] }

        if let translationLRC, !translationLRC.isEmpty {
            let translations = parseSingle(translationLRC)
            if !translations.isEmpty {
                primary = merge(primary: primary, translations: translations)
            }
        }

        return primary
    }

    /// Finds the active lyric line at a given playback timestamp.
    public static func activeLine(in lines: [LyricLine], at time: TimeInterval) -> LyricLine? {
        guard !lines.isEmpty, time >= 0 else { return nil }

        // Slight lead-in (0.15s) makes lyric transitions feel snappier visually.
        let adjusted = time + 0.15
        guard adjusted >= lines[0].time else { return nil }

        var low = 0
        var high = lines.count - 1
        var matchIndex = -1

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= adjusted {
                matchIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard matchIndex >= 0 else { return nil }
        let candidate = lines[matchIndex]
        if candidate.text.isEmpty {
            return nil
        }
        return candidate
    }

    private static func parseSingle(_ raw: String) -> [LyricLine] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var offsetSeconds: TimeInterval = 0
        var results: [LyricLine] = []

        // Matches [mm:ss], [mm:ss.xx], [mm:ss.xxx], [mm:ss:xx]
        let tagRegex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetRegex = try? NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)

        for lineSub in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSub).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if let offsetMatch = offsetRegex?.firstMatch(in: line, range: fullRange),
               offsetMatch.numberOfRanges >= 2 {
                let msStr = nsLine.substring(with: offsetMatch.range(at: 1))
                if let ms = Double(msStr) {
                    offsetSeconds = ms / 1000.0
                }
                continue
            }

            guard let matches = tagRegex?.matches(in: line, range: fullRange), !matches.isEmpty else {
                continue
            }

            let lastEnd = matches.last!.range.location + matches.last!.range.length
            let text = nsLine.substring(from: lastEnd)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            // Skip common credit metadata lines at t=0 if they are pure metadata markers
            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0

                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound {
                    let fracStr = nsLine.substring(with: match.range(at: 3))
                    if let val = Double(fracStr) {
                        switch fracStr.count {
                        case 1: fraction = val / 10.0
                        case 2: fraction = val / 100.0
                        default: fraction = val / 1000.0
                        }
                    }
                }

                let timestamp = max(0, minutes * 60.0 + seconds + fraction - offsetSeconds)
                results.append(LyricLine(time: timestamp, text: text))
            }
        }

        // Sort chronologically and deduplicate identical timestamps keeping the last non-empty text
        results.sort { $0.time < $1.time }

        var cleaned: [LyricLine] = []
        cleaned.reserveCapacity(results.count)
        for item in results {
            if let last = cleaned.last, abs(last.time - item.time) < 0.01 {
                if !item.text.isEmpty {
                    cleaned[cleaned.count - 1] = item
                }
            } else {
                cleaned.append(item)
            }
        }

        // Remove trailing blank instrumental markers at the very start
        while let first = cleaned.first, first.text.isEmpty {
            cleaned.removeFirst()
        }

        return cleaned
    }

    private static func merge(primary: [LyricLine], translations: [LyricLine]) -> [LyricLine] {
        var merged = primary
        for index in merged.indices {
            guard !merged[index].text.isEmpty else { continue }
            let targetTime = merged[index].time

            var bestMatch: LyricLine?
            var bestDelta: TimeInterval = 0.45

            for candidate in translations where !candidate.text.isEmpty {
                let delta = abs(candidate.time - targetTime)
                if delta < bestDelta {
                    bestDelta = delta
                    bestMatch = candidate
                }
            }

            if let match = bestMatch, match.text.lowercased() != merged[index].text.lowercased() {
                merged[index].translation = match.text
            }
        }
        return merged
    }
}
