import Foundation

struct DailyAyah: Equatable {
    let target: QuranCitationTarget
    let surahName: String?
    let arabicText: String
    let translationText: String?

    var surahId: Int { target.surahId }
    var ayah: Int { target.ayah }
    var verseId: String { target.verseId }
    var referenceText: String { "\(surahId):\(ayah)" }
    var displayReferenceText: String {
        let trimmedName = surahName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? referenceText : "\(trimmedName) \(referenceText)"
    }
}

enum DailyAyahProvider {
    // A small, stable rotation list for deterministic daily selection.
    private static let rotatingVerseIds: [String] = [
        "1:1",
        "2:255",
        "2:286",
        "3:8",
        "12:87",
        "13:28",
        "17:24",
        "18:10",
        "39:53",
        "94:5",
    ]

    static func dailyAyah(
        on date: Date = Date(),
        bundle: Bundle = .main,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DailyAyah {
        let target = targetForDate(date, calendar: calendar) ?? QuranCitationTarget(surahId: 1, ayah: 1)

        guard let repository = QuranRepository(bundle: bundle) else {
            return DailyAyah(target: target, surahName: nil, arabicText: "", translationText: nil)
        }

        let surahName = repository
            .loadSurahs()
            .first(where: { $0.id == target.surahId })?
            .name

        if let verse = repository.loadVerse(for: target.surahId, ayah: target.ayah, includeTranslation: true) {
            return DailyAyah(
                target: target,
                surahName: surahName,
                arabicText: verse.arabicText,
                translationText: verse.translationText
            )
        }

        return DailyAyah(target: target, surahName: surahName, arabicText: "", translationText: nil)
    }

    static func isJummahWindow(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        var calendar = calendar
        calendar.timeZone = .current
        let weekday = calendar.component(.weekday, from: date)
        guard weekday == 6 else { return false } // Friday in the Gregorian calendar.
        let hour = calendar.component(.hour, from: date)
        return hour >= 6 && hour < 15
    }

    static func nextRefreshDate(
        after date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = .current

        let startOfDay = calendar.startOfDay(for: date)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86_400)

        let fridaySix = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 6, minute: 0, second: 0, weekday: 6),
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
        let fridayFifteen = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 15, minute: 0, second: 0, weekday: 6),
            matchingPolicy: .nextTimePreservingSmallerComponents
        )

        let candidates = [nextMidnight, fridaySix, fridayFifteen]
            .compactMap { $0 }
            .filter { $0 > date }

        return candidates.min() ?? nextMidnight
    }

    private static func targetForDate(
        _ date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> QuranCitationTarget? {
        guard !rotatingVerseIds.isEmpty else { return nil }
        var calendar = calendar
        calendar.timeZone = .current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = (dayOfYear - 1) % rotatingVerseIds.count
        return QuranDeepLink.parseVerseId(rotatingVerseIds[index])
    }
}
