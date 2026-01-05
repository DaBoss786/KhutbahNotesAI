import Foundation

struct Surah: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct QuranVerse: Identifiable, Hashable {
    let surahNumber: Int
    let ayahNumber: Int
    let arabicText: String
    let translationText: String?

    var id: String {
        "\(surahNumber):\(ayahNumber)"
    }
}

enum QuranTranslationOption: String, CaseIterable, Identifiable {
    case off = "Off"
    case english = "English"

    var id: String {
        rawValue
    }
}
