import Foundation
import Testing
@testable import VinylDesk

@Suite("LRCParser Tests")
struct LRCParserTests {
    @Test("Parses standard LRC with multiple timestamps and millisecond precision")
    func parseStandardAndMultiTimestamp() {
        let lrc = """
        [ti:Sample Track]
        [ar:Artist]
        [00:01.20]First line
        [00:05.500][00:15.00]Repeated chorus
        [00:10.00]Second verse
        """

        let lines = LRCParser.parse(lrc: lrc)
        #expect(lines.count == 4)
        #expect(lines[0].text == "First line")
        #expect(abs(lines[0].time - 1.2) < 0.001)
        #expect(lines[1].text == "Repeated chorus")
        #expect(abs(lines[1].time - 5.5) < 0.001)
        #expect(lines[2].text == "Second verse")
        #expect(lines[3].text == "Repeated chorus")
        #expect(abs(lines[3].time - 15.0) < 0.001)
    }

    @Test("Merges bilingual translation LRC accurately")
    func mergeBilingualTranslations() {
        let orig = """
        [00:12.00]Hello from the other side
        [00:16.50]I must've called a thousand times
        """
        let trans = """
        [00:12.10]来自彼岸的问候
        [00:16.45]我一定打过上千次电话
        """

        let lines = LRCParser.parse(lrc: orig, translationLRC: trans)
        #expect(lines.count == 2)
        #expect(lines[0].translation == "来自彼岸的问候")
        #expect(lines[1].translation == "我一定打过上千次电话")
    }

    @Test("Finds active line using binary search with subtle visual lead-in")
    func activeLineLookup() {
        let lines = [
            LyricLine(time: 5.0, text: "Line 1"),
            LyricLine(time: 10.0, text: "Line 2"),
            LyricLine(time: 15.0, text: "Line 3")
        ]

        #expect(LRCParser.activeLine(in: lines, at: 1.0) == nil)
        #expect(LRCParser.activeLine(in: lines, at: 5.0)?.text == "Line 1")
        #expect(LRCParser.activeLine(in: lines, at: 9.9)?.text == "Line 2")
        #expect(LRCParser.activeLine(in: lines, at: 20.0)?.text == "Line 3")
    }

    @Test("Applies offset tag properly")
    func offsetSupport() {
        let lrc = """
        [offset:500]
        [00:10.00]Shifted line
        """
        let lines = LRCParser.parse(lrc: lrc)
        #expect(lines.count == 1)
        #expect(abs(lines[0].time - 9.5) < 0.001)
    }
}
