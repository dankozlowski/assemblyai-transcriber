import XCTest
@testable import Transcriber

final class TranscriptionServiceTests: XCTestCase {

    func testParseBeginEvent() throws {
        let json = """
        {"type": "Begin", "id": "abc-123", "expires_at": "2026-04-12T14:30:00Z"}
        """
        let event = try TranscriptionService.parseEvent(Data(json.utf8))
        guard case .begin(let id, _) = event else {
            XCTFail("Expected begin event"); return
        }
        XCTAssertEqual(id, "abc-123")
    }

    func testParseTurnEventPartial() throws {
        let json = """
        {"type": "Turn", "turn_order": 0, "end_of_turn": false, "transcript": "hello", "speaker_label": "A"}
        """
        let event = try TranscriptionService.parseEvent(Data(json.utf8))
        guard case .turn(let speaker, let text, let endOfTurn) = event else {
            XCTFail("Expected turn event"); return
        }
        XCTAssertEqual(speaker, "A")
        XCTAssertEqual(text, "hello")
        XCTAssertFalse(endOfTurn)
    }

    func testParseTurnEventFinal() throws {
        let json = """
        {"type": "Turn", "turn_order": 1, "end_of_turn": true, "transcript": "hello world", "speaker_label": "B"}
        """
        let event = try TranscriptionService.parseEvent(Data(json.utf8))
        guard case .turn(let speaker, let text, let endOfTurn) = event else {
            XCTFail("Expected turn event"); return
        }
        XCTAssertEqual(speaker, "B")
        XCTAssertTrue(endOfTurn)
    }

    func testParseTerminationEvent() throws {
        let json = """
        {"type": "Termination", "audio_duration_seconds": 300, "session_duration_seconds": 305}
        """
        let event = try TranscriptionService.parseEvent(Data(json.utf8))
        guard case .termination(let audioDuration) = event else {
            XCTFail("Expected termination event"); return
        }
        XCTAssertEqual(audioDuration, 300)
    }

    func testParseErrorEvent() throws {
        let json = """
        {"error": "insufficient funds"}
        """
        let event = try TranscriptionService.parseEvent(Data(json.utf8))
        guard case .error(let message) = event else {
            XCTFail("Expected error event"); return
        }
        XCTAssertEqual(message, "insufficient funds")
    }
}
