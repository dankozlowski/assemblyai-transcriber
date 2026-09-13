import XCTest
@testable import Transcriber

final class SessionConfigTests: XCTestCase {
    func testDefaults() {
        let config = SessionConfig()
        XCTAssertEqual(config.sessionName, "")
        XCTAssertEqual(config.maxSpeakers, 2)
        XCTAssertEqual(config.maxDurationMinutes, 240)
        XCTAssertEqual(config.silenceTimeoutMinutes, 5)
        XCTAssertEqual(config.inactivityTimeoutMinutes, 5)
        XCTAssertFalse(config.recordAudio)
    }

    func testSlug() {
        let config = SessionConfig(sessionName: "My Test Session!")
        let slug = config.fileSlug
        XCTAssertEqual(slug, "my_test_session")
        XCTAssertFalse(slug.contains(" "))
        XCTAssertFalse(slug.contains("!"))
    }

    func testEmptyNameSlug() {
        let config = SessionConfig(sessionName: "")
        XCTAssertEqual(config.fileSlug, "transcript")
    }
}
