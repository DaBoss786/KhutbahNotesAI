import XCTest
@testable import Khutbah_Notes_AI

final class DailyAyahProviderTests: XCTestCase {
    private let repositoryBundle = Bundle(for: QuranRepository.self)

    func testDailyAyahStableWithinSameDay() {
        let morning = makeDate(year: 2026, month: 1, day: 15, hour: 9, minute: 5)
        let evening = makeDate(year: 2026, month: 1, day: 15, hour: 21, minute: 55)

        let first = DailyAyahProvider.dailyAyah(on: morning, bundle: repositoryBundle)
        let second = DailyAyahProvider.dailyAyah(on: evening, bundle: repositoryBundle)

        XCTAssertEqual(first.verseId, second.verseId)
    }

    func testHourlyAyahStableWithinSameHour() {
        let early = makeDate(year: 2026, month: 1, day: 15, hour: 10, minute: 5)
        let late = makeDate(year: 2026, month: 1, day: 15, hour: 10, minute: 55)

        let first = DailyAyahProvider.hourlyAyah(on: early, bundle: repositoryBundle)
        let second = DailyAyahProvider.hourlyAyah(on: late, bundle: repositoryBundle)

        XCTAssertEqual(first.verseId, second.verseId)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to build date from components.")
            return Date()
        }
        return date
    }
}
