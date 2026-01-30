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

    // Curated rotation list for deterministic daily/hourly selection.
    private static let rotatingVerseIds: [String] = [
        "1:1", "1:2", "1:3", "1:4", "1:5", "1:6", "1:7", "2:2", "2:21", "2:22",
        "2:25", "2:30", "2:37", "2:45", "2:62", "2:83", "2:115", "2:152", "2:153", "2:155",
        "2:156", "2:158", "2:163", "2:165", "2:177", "2:186", "2:190", "2:195", "2:197", "2:201",
        "2:214", "2:216", "2:222", "2:238", "2:255", "2:256", "2:261", "2:263", "2:267", "2:268",
        "2:269", "2:277", "2:280", "2:284", "2:285", "2:286", "3:8", "3:9", "3:18", "3:26",
        "3:31", "3:37", "3:54", "3:57", "3:92", "3:102", "3:104", "3:110", "3:133", "3:134",
        "3:139", "3:146", "3:159", "3:160", "3:169", "3:173", "3:185", "3:190", "3:191", "3:200",
        "4:1", "4:36", "4:40", "4:58", "4:59", "4:86", "4:93", "4:100", "4:110", "4:114",
        "4:135", "4:147", "4:148", "4:149", "4:156", "4:162", "4:171", "4:175", "4:176", "5:1",
        "5:2", "5:3", "5:8", "5:32", "5:48", "5:54", "5:55", "5:57", "5:83", "5:90",
        "5:91", "5:93", "5:97", "5:100", "6:12", "6:17", "6:38", "6:54", "6:59", "6:60",
        "6:95", "6:102", "6:141", "6:151", "6:152", "6:153", "7:23", "7:31", "7:35", "7:56",
        "7:57", "7:96", "7:143", "7:156", "7:179", "7:199", "7:204", "7:205", "8:24", "8:29",
        "8:46", "8:61", "8:63", "8:74", "9:5", "9:20", "9:40", "9:51", "9:71", "9:100",
        "9:105", "9:111", "9:119", "9:128", "9:129", "10:5", "10:57", "10:62", "10:99", "10:107",
        "10:109", "11:6", "11:9", "11:11", "11:88", "11:90", "11:114", "12:18", "12:33", "12:53",
        "12:64", "12:86", "12:87", "13:11", "13:28", "13:29", "13:38", "14:7", "14:11", "14:24",
        "14:41", "16:18", "16:90", "16:97", "16:98", "16:125", "16:128", "17:7", "17:23", "17:24",
        "17:32", "17:36", "17:53", "17:70", "17:78", "17:81", "17:82", "18:10", "18:13", "18:29",
        "18:46", "18:49", "18:110", "18:107", "18:109", "19:1", "19:58", "19:96", "19:97", "20:8",
        "20:14", "20:25", "20:46", "20:82", "20:114", "20:124", "20:130", "21:30", "21:35", "21:83",
        "21:87", "21:107", "22:5", "22:11", "22:32", "22:46", "22:77", "23:1", "23:2", "23:57",
        "23:60", "23:97", "24:21", "24:26", "24:27", "24:30", "24:31", "24:35", "24:58", "24:61",
        "25:20", "25:53", "25:63", "25:70", "25:71", "25:74", "25:77", "26:80", "26:83", "26:88",
        "27:19", "27:30", "27:40", "28:7", "28:14", "28:77", "28:83", "29:2", "29:45", "29:56",
        "29:69", "29:57", "30:21", "30:30", "30:41", "30:60", "30:46", "31:12", "31:13", "31:14",
        "31:15", "31:17", "31:18", "31:19", "31:34", "32:7", "32:9", "33:21", "33:35", "33:41",
        "33:56", "33:70", "33:71", "33:72", "34:3", "34:46", "35:3", "35:28", "36:12", "36:58",
        "36:77", "36:82", "36:83", "37:96", "37:180", "38:26", "38:29", "39:9", "39:10", "39:18",
        "39:21", "39:53", "39:60", "39:62", "40:7", "40:40", "40:60", "41:30", "41:34", "41:53",
        "42:36", "42:38", "42:40", "43:36", "43:43", "44:3", "45:15", "46:15", "47:7", "48:4",
        "49:10", "49:11", "49:12", "49:13", "49:14", "49:15", "49:18", "50:16", "50:31", "51:21",
        "51:56", "52:21", "55:1", "55:13", "55:29", "55:60", "56:57", "56:60", "56:79", "56:96",
        "57:4", "57:10", "57:20", "57:21", "57:25", "58:11", "59:9", "59:18", "59:19", "59:20",
        "59:21", "59:22", "59:23", "59:24", "60:8", "61:2", "62:10", "64:2", "64:11", "64:16",
        "65:2", "65:3", "65:7", "66:8", "66:11", "67:1", "67:15", "67:30", "68:4", "71:10",
        "72:16", "73:20", "93:5", "94:6", "103:1",
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
        let seed: UInt64
        switch cadence {
        case .daily:
            seed = UInt64(dayOfYear)
        case .hourly:
            seed = UInt64(dayOfYear * 24 + hour)
        }
        var generator = SeededGenerator(seed: seed)
        let index = Int.random(in: 0..<rotatingVerseIds.count, using: &generator)
        return QuranDeepLink.parseVerseId(rotatingVerseIds[index])
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
