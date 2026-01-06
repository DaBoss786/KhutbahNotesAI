import XCTest
@testable import Khutbah_Notes_AI

final class QuranRepositoryTests: XCTestCase {
    private func makeRepository(file: StaticString = #filePath, line: UInt = #line) -> QuranRepository? {
        let bundle = Bundle(for: QuranRepository.self)
        let repository = QuranRepository(bundle: bundle)
        if repository == nil {
            XCTFail("Failed to load Quran data from bundle.", file: file, line: line)
        }
        return repository
    }

    func testLoadSurahsHasExpectedFirstEntry() {
        guard let repository = makeRepository() else { return }
        let surahs = repository.loadSurahs()

        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(surahs.first?.id, 1)
        XCTAssertEqual(surahs.first?.name, "Al-Fatihah")
    }

    func testLoadVersesForSurahOneCountAndStripsDigits() {
        guard let repository = makeRepository() else { return }
        let verses = repository.loadVerses(for: 1, includeTranslation: false)

        XCTAssertEqual(verses.count, 7)
        XCTAssertEqual(verses.first?.ayahNumber, 1)
        XCTAssertFalse(endsWithDigit(verses.first?.arabicText ?? ""))
    }

    func testLoadVersesIncludesTranslationWhenEnabled() {
        guard let repository = makeRepository() else { return }
        let verses = repository.loadVerses(for: 1, includeTranslation: true)

        XCTAssertFalse(verses.isEmpty)
        XCTAssertNotNil(verses.first?.translationText)
        XCTAssertFalse(verses.first?.translationText?.isEmpty ?? true)
    }

    private func endsWithDigit(_ text: String) -> Bool {
        guard let lastScalar = text.unicodeScalars.last else { return false }
        return CharacterSet.decimalDigits.contains(lastScalar)
    }
}
