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
}
