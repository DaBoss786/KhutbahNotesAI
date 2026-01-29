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
    enum AyahCadence {
        case daily
        case hourly
    }

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
        ayah(on: date, cadence: .daily, bundle: bundle, calendar: calendar)
    }

    static func hourlyAyah(
        on date: Date = Date(),
        bundle: Bundle = .main,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DailyAyah {
        ayah(on: date, cadence: .hourly, bundle: bundle, calendar: calendar)
    }

    static func ayah(
        on date: Date = Date(),
        cadence: AyahCadence,
        bundle: Bundle = .main,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DailyAyah {
        let target = targetForDate(date, cadence: cadence, calendar: calendar)
            ?? QuranCitationTarget(surahId: 1, ayah: 1)

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
        cadence: AyahCadence,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = .current

        let startOfDay = calendar.startOfDay(for: date)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? date.addingTimeInterval(86_400)
        let nextHourBase = calendar.date(byAdding: .hour, value: 1, to: date)
            ?? date.addingTimeInterval(3_600)
        let nextHour = calendar.date(
            bySettingHour: calendar.component(.hour, from: nextHourBase),
            minute: 0,
            second: 0,
            of: nextHourBase
        ) ?? nextHourBase

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

        let cadenceRefresh = cadence == .hourly ? nextHour : nextMidnight
        let candidates = [cadenceRefresh, fridaySix, fridayFifteen]
            .compactMap { $0 }
            .filter { $0 > date }

        return candidates.min() ?? cadenceRefresh
    }

    private static func targetForDate(
        _ date: Date,
        cadence: AyahCadence,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> QuranCitationTarget? {
        guard !rotatingVerseIds.isEmpty else { return nil }
        var calendar = calendar
        calendar.timeZone = .current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour = calendar.component(.hour, from: date)
        let rotationIndex: Int
        switch cadence {
        case .daily:
            rotationIndex = dayOfYear - 1
        case .hourly:
            rotationIndex = (dayOfYear - 1) * 24 + hour
        }
        let index = rotationIndex % rotatingVerseIds.count
        return QuranDeepLink.parseVerseId(rotatingVerseIds[index])
    }
}
