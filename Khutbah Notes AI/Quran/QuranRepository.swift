import Foundation
import SQLite3

final class QuranRepository {
    private let arabicDatabase: OpaquePointer?
    private let translationDatabase: OpaquePointer?
    private let surahDatabase: OpaquePointer?
    private let trailingTrimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{00A0}"))
    private let arabicDigits = CharacterSet(charactersIn: "٠١٢٣٤٥٦٧٨٩")

    init?(
        bundle: Bundle = .main,
        arabicFilename: String = "quran_ar",
        arabicExtension: String = "sqlite",
        translationFilename: String = "quran_en_sahih",
        translationExtension: String = "db",
        surahFilename: String = "quran-metadata-surah-name",
        surahExtension: String = "sqlite"
    ) {
        guard
            let arabicPath = bundle.path(forResource: arabicFilename, ofType: arabicExtension),
            let translationPath = bundle.path(forResource: translationFilename, ofType: translationExtension),
            let surahPath = bundle.path(forResource: surahFilename, ofType: surahExtension)
        else {
            arabicDatabase = nil
            translationDatabase = nil
            surahDatabase = nil
            return nil
        }

        guard
            let arabicDatabase = QuranRepository.openDatabase(at: arabicPath),
            let translationDatabase = QuranRepository.openDatabase(at: translationPath),
            let surahDatabase = QuranRepository.openDatabase(at: surahPath)
        else {
            return nil
        }

        self.arabicDatabase = arabicDatabase
        self.translationDatabase = translationDatabase
        self.surahDatabase = surahDatabase
    }

    deinit {
        closeDatabase(arabicDatabase)
        closeDatabase(translationDatabase)
        closeDatabase(surahDatabase)
    }

    func loadSurahs() -> [Surah] {
        guard let surahDatabase else { return [] }
        let query = "SELECT id, name_simple FROM chapters ORDER BY id;"
        var statement: OpaquePointer?
        var surahs: [Surah] = []

        if sqlite3_prepare_v2(surahDatabase, query, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = stringValue(from: statement, index: 1)
                surahs.append(Surah(id: id, name: name))
            }
        }

        return surahs
    }

    func loadVerses(for surahId: Int, includeTranslation: Bool) -> [QuranVerse] {
        guard let arabicDatabase else { return [] }
        let translationMap = includeTranslation ? loadEnglishTranslations(for: surahId) : [:]
        let query = "SELECT ayah_number, text FROM verses WHERE surah_number = ? ORDER BY ayah_number;"
        var statement: OpaquePointer?
        var verses: [QuranVerse] = []

        if sqlite3_prepare_v2(arabicDatabase, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(surahId))
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let ayah = Int(sqlite3_column_int(statement, 0))
                let arabicText = stringValue(from: statement, index: 1)
                let cleanedArabicText = stripTrailingArabicNumber(from: arabicText)
                let translationText = translationMap[ayah]
                verses.append(
                    QuranVerse(
                        surahNumber: surahId,
                        ayahNumber: ayah,
                        arabicText: cleanedArabicText,
                        translationText: translationText
                    )
                )
            }
        }

        return verses
    }

    func loadVerse(for surahId: Int, ayah: Int, includeTranslation: Bool) -> QuranVerse? {
        guard let arabicDatabase else { return nil }
        let translationText = includeTranslation ? loadEnglishTranslation(for: surahId, ayah: ayah) : nil
        let query = """
            SELECT text
            FROM verses
            WHERE surah_number = ? AND ayah_number = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(arabicDatabase, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(surahId))
            sqlite3_bind_int(statement, 2, Int32(ayah))
            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW {
                let arabicText = stringValue(from: statement, index: 0)
                let cleanedArabicText = stripTrailingArabicNumber(from: arabicText)
                return QuranVerse(
                    surahNumber: surahId,
                    ayahNumber: ayah,
                    arabicText: cleanedArabicText,
                    translationText: translationText
                )
            }
        }

        return nil
    }

    private func loadEnglishTranslations(for surahId: Int) -> [Int: String] {
        guard let translationDatabase else { return [:] }
        let query = "SELECT ayah, text FROM translation WHERE sura = ? ORDER BY ayah;"
        var statement: OpaquePointer?
        var translations: [Int: String] = [:]

        if sqlite3_prepare_v2(translationDatabase, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(surahId))
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let ayah = Int(sqlite3_column_int(statement, 0))
                let text = stringValue(from: statement, index: 1)
                translations[ayah] = text
            }
        }

        return translations
    }

    private func loadEnglishTranslation(for surahId: Int, ayah: Int) -> String? {
        guard let translationDatabase else { return nil }
        let query = """
            SELECT text
            FROM translation
            WHERE sura = ? AND ayah = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(translationDatabase, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(surahId))
            sqlite3_bind_int(statement, 2, Int32(ayah))
            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW {
                return stringValue(from: statement, index: 0)
            }
        }

        return nil
    }

    private func stringValue(from statement: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func stripTrailingArabicNumber(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: trailingTrimSet)
        var scalars = trimmed.unicodeScalars
        var endIndex = scalars.endIndex
        var stripped = false

        while endIndex > scalars.startIndex {
            let previousIndex = scalars.index(before: endIndex)
            let scalar = scalars[previousIndex]
            if arabicDigits.contains(scalar) || trailingTrimSet.contains(scalar) {
                endIndex = previousIndex
                stripped = true
            } else {
                break
            }
        }

        if !stripped {
            return trimmed
        }

        let result = String(String.UnicodeScalarView(scalars[..<endIndex]))
        return result.trimmingCharacters(in: trailingTrimSet)
    }

    private static func openDatabase(at path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        if result == SQLITE_OK {
            return database
        }
        if database != nil {
            sqlite3_close(database)
        }
        return nil
    }

    private func closeDatabase(_ database: OpaquePointer?) {
        guard let database else { return }
        sqlite3_close(database)
    }
}
