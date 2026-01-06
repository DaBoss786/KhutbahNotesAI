import Foundation

struct QuranCitation {
    let surahId: Int
    let ayah: Int
}

struct QuranCitationParser {
    private static let citationRegex = try? NSRegularExpression(
        pattern: "(\\d{1,3})\\s*[:.]\\s*(\\d{1,3})",
        options: []
    )
    private static let arabicDigitMap: [Character: Character] = [
        "٠": "0",
        "١": "1",
        "٢": "2",
        "٣": "3",
        "٤": "4",
        "٥": "5",
        "٦": "6",
        "٧": "7",
        "٨": "8",
        "٩": "9"
    ]

    static func parse(_ text: String) -> QuranCitation? {
        guard let citationRegex else { return nil }
        let normalized = normalizeDigits(in: text)
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = citationRegex.firstMatch(in: normalized, range: range),
              let surahRange = Range(match.range(at: 1), in: normalized),
              let ayahRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        guard let surahId = Int(normalized[surahRange]),
              let ayah = Int(normalized[ayahRange]),
              (1...114).contains(surahId),
              ayah > 0
        else {
            return nil
        }

        return QuranCitation(surahId: surahId, ayah: ayah)
    }

    private static func normalizeDigits(in text: String) -> String {
        String(text.map { arabicDigitMap[$0] ?? $0 })
    }
}
