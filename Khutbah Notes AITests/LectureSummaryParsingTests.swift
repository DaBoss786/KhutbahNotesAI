import XCTest
@testable import Khutbah_Notes_AI

final class LectureSummaryParsingTests: XCTestCase {
    func testParseSummaryNilReturnsNil() {
        let summary = LectureSummaryParser.parseSummary(from: nil)
        XCTAssertNil(summary)
    }

    func testParseSummaryDefaultsForMissingFields() {
        let summary = LectureSummaryParser.parseSummary(from: [:])
        XCTAssertEqual(summary?.mainTheme, "Not mentioned")
        XCTAssertEqual(summary?.keyPoints, [])
        XCTAssertEqual(summary?.explicitAyatOrHadith, [])
        XCTAssertEqual(summary?.weeklyActions, [])
    }

    func testParseSummaryInProgressLegacyBoolean() {
        let legacy = LectureSummaryParser.parseSummaryInProgress(from: true)
        XCTAssertEqual(legacy?.isLegacy, true)
        XCTAssertNil(legacy?.startedAt)
        XCTAssertNil(legacy?.expiresAt)

        let cleared = LectureSummaryParser.parseSummaryInProgress(from: false)
        XCTAssertNil(cleared)
    }

    func testParseSummaryInProgressMapWithoutTimestampsReturnsNil() {
        let state = LectureSummaryParser.parseSummaryInProgress(from: [
            "startedAt": "not a timestamp",
        ])

        XCTAssertNil(state)
    }

    func testParseSummaryTranslationsSkipsInvalidAndSorts() {
        let summaryMap: [String: Any] = [
            "mainTheme": "Theme",
            "keyPoints": ["Point"],
            "explicitAyatOrHadith": [],
            "weeklyActions": ["Act"],
        ]
        let translations = LectureSummaryParser.parseSummaryTranslations(from: [
            "ur": summaryMap,
            "bad": "not a map",
            "ar": summaryMap,
        ])

        XCTAssertEqual(translations.map { $0.languageCode }, ["ar", "ur"])
    }

    func testParseTranslationErrorsFiltersEmptyAndSorts() {
        let errors = LectureSummaryParser.parseTranslationErrors(from: [
            "fr": "",
            "es": 123,
            "ar": "Failed to translate",
        ])

        XCTAssertEqual(errors.map { $0.languageCode }, ["ar"])
        XCTAssertEqual(errors.first?.message, "Failed to translate")
    }

    func testTranslationKeysHandlesDifferentMaps() {
        let anyKeys = LectureSummaryParser.translationKeys(from: [
            "b": 1,
            "a": 2,
        ])
        XCTAssertEqual(anyKeys, ["a", "b"])

        let boolKeys = LectureSummaryParser.translationKeys(from: [
            "d": true,
            "c": false,
        ] as [String: Bool])
        XCTAssertEqual(boolKeys, ["c", "d"])
    }
}
