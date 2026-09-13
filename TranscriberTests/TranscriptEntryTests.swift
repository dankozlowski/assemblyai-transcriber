import XCTest
@testable import Transcriber

final class TranscriptEntryTests: XCTestCase {
    func testFinalEntry() {
        let entry = TranscriptEntry(speaker: "A", text: "Hello world", isFinal: true)
        XCTAssertEqual(entry.speaker, "A")
        XCTAssertEqual(entry.text, "Hello world")
        XCTAssertTrue(entry.isFinal)
    }

    func testPartialEntry() {
        let entry = TranscriptEntry(speaker: "B", text: "partial", isFinal: false)
        XCTAssertFalse(entry.isFinal)
    }

    func testMarkdownFormat() {
        let entry = TranscriptEntry(speaker: "A", text: "Hello world", isFinal: true)
        let md = entry.markdownLine
        XCTAssertTrue(md.contains("**"))
        XCTAssertTrue(md.contains("A"))
        XCTAssertTrue(md.contains("Hello world"))
    }
}
