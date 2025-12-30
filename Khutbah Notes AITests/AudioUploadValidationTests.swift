import XCTest
@testable import Khutbah_Notes_AI

final class AudioUploadValidationTests: XCTestCase {
    private let supportedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "m4b", "aif", "aiff", "caf"
    ]
    private let maxUploadBytes: Int64 = 100 * 1024 * 1024

    func testUnsupportedFileTypeReturnsError() {
        let error = LectureStore.audioUploadValidationError(
            fileExtension: "txt",
            fileSizeBytes: 128,
            supportedExtensions: supportedExtensions,
            maxFileSizeBytes: maxUploadBytes
        )

        guard case .unsupportedFileType? = error else {
            XCTFail("Expected unsupportedFileType, got \(String(describing: error))")
            return
        }
    }

    func testOversizedFileReturnsError() {
        let error = LectureStore.audioUploadValidationError(
            fileExtension: "m4a",
            fileSizeBytes: maxUploadBytes + 1,
            supportedExtensions: supportedExtensions,
            maxFileSizeBytes: maxUploadBytes
        )

        guard case .fileTooLarge? = error else {
            XCTFail("Expected fileTooLarge, got \(String(describing: error))")
            return
        }
    }

    func testValidFileExtensionPasses() {
        let error = LectureStore.audioUploadValidationError(
            fileExtension: "mp3",
            fileSizeBytes: 1024,
            supportedExtensions: supportedExtensions,
            maxFileSizeBytes: maxUploadBytes
        )

        XCTAssertNil(error)
    }

    func testDurationMinutesRoundsWithMinimumOne() {
        XCTAssertEqual(LectureStore.durationMinutes(fromSeconds: 1), 1)
        XCTAssertEqual(LectureStore.durationMinutes(fromSeconds: 59), 1)
        XCTAssertEqual(LectureStore.durationMinutes(fromSeconds: 90), 2)
    }
}
