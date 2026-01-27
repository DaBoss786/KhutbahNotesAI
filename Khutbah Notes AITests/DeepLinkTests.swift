import XCTest
@testable import Khutbah_Notes_AI

final class DeepLinkTests: XCTestCase {
    func testLectureDeepLinkParsesLectureId() {
        let url = URL(string: "khutbahnotesai://lecture?lectureId=abc123")!
        XCTAssertEqual(LectureDeepLink.lectureId(from: url), "abc123")
    }

    func testLectureDeepLinkRejectsWrongScheme() {
        let url = URL(string: "otherapp://lecture?lectureId=abc123")!
        XCTAssertNil(LectureDeepLink.lectureId(from: url))
    }

    func testLectureDeepLinkRejectsWrongHost() {
        let url = URL(string: "khutbahnotesai://recording?lectureId=abc123")!
        XCTAssertNil(LectureDeepLink.lectureId(from: url))
    }

    func testLectureDeepLinkRejectsMissingLectureId() {
        let url = URL(string: "khutbahnotesai://lecture")!
        XCTAssertNil(LectureDeepLink.lectureId(from: url))
    }

    func testLectureDeepLinkTrimsWhitespace() {
        let url = URL(string: "khutbahnotesai://lecture?lectureId=%20id%20")!
        XCTAssertEqual(LectureDeepLink.lectureId(from: url), "id")
    }

    func testQuranDeepLinkParsesSurahAndAyah() {
        let url = URL(string: "khutbahnotesai://quran?surah=2&ayah=255")!
        let target = QuranDeepLink.target(from: url)
        XCTAssertEqual(target?.surahId, 2)
        XCTAssertEqual(target?.ayah, 255)
    }

    func testQuranDeepLinkParsesId() {
        let url = URL(string: "khutbahnotesai://quran?id=18:10")!
        let target = QuranDeepLink.target(from: url)
        XCTAssertEqual(target?.surahId, 18)
        XCTAssertEqual(target?.ayah, 10)
    }

    func testQuranDeepLinkRejectsWrongHost() {
        let url = URL(string: "khutbahnotesai://recording?surah=2&ayah=255")!
        XCTAssertNil(QuranDeepLink.target(from: url))
    }
}
