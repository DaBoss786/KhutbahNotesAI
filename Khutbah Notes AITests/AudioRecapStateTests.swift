import XCTest
@testable import Khutbah_Notes_AI

final class AudioRecapStateTests: XCTestCase {
    func testParseReadyRecapState() {
        let json: [String: Any] = [
            "status": "ready",
            "variantKey": "abc123",
            "audioPath": "audio/u1/recaps/l1/abc123.mp3",
            "script": "Short recap text",
            "durationSec": 94,
            "voice": "male",
            "style": "concise",
            "language": "en",
            "targetLengthSec": 120,
            "promptVersion": "v1",
            "stale": false,
        ]

        let state = AudioRecapStateParser.parse(from: json)
        XCTAssertEqual(state.status, .ready)
        XCTAssertEqual(state.variantKey, "abc123")
        XCTAssertEqual(state.audioPath, "audio/u1/recaps/l1/abc123.mp3")
        XCTAssertEqual(state.durationSec, 94)
        XCTAssertEqual(state.voice, .male)
        XCTAssertEqual(state.style, .concise)
        XCTAssertEqual(state.targetLengthSec, 120)
        XCTAssertFalse(state.stale)
    }

    func testParseUnknownStatusFallsBackToMissing() {
        let json: [String: Any] = [
            "status": "unexpected",
            "variantKey": "k1",
        ]

        let state = AudioRecapStateParser.parse(from: json)
        XCTAssertEqual(state.status, .missing)
    }

    func testUnavailableFactoryProducesErrorState() {
        let state = AudioRecapState.unavailable(
            message: "Transcript unavailable.",
            variantKey: "v1"
        )

        XCTAssertEqual(state.status, .unavailable)
        XCTAssertEqual(state.variantKey, "v1")
        XCTAssertEqual(state.errorMessage, "Transcript unavailable.")
        XCTAssertNotNil(state.userMessage)
    }

    func testOptionsUseFixedThreeMinuteTarget() {
        let options = AudioRecapOptions()
        XCTAssertEqual(options.clampedLengthSec, 180)
        XCTAssertEqual(options.targetLengthSec, 180)
        XCTAssertEqual(
            options.requestBody["targetLengthSec"] as? Int,
            180
        )
    }
}
