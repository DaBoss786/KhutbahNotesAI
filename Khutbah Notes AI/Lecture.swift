//
//  Lecture.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import Foundation

enum LectureStatus: String, Codable, Hashable {
    case recording
    case processing
    case ready
    case failed
}

struct Lecture: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date
    var durationMinutes: Int?
    var isFavorite: Bool
    var status: LectureStatus
    var transcript: String?
    var summary: LectureSummary?
    var audioPath: String?
}

extension Lecture {
    static let mock = Lecture(
        id: "mock-1",
        title: "Tafseer of Surah Al-Kahf",
        date: Date(),
        durationMinutes: 45,
        isFavorite: true,
        status: .ready,
        transcript: "Sample transcript...",
        summary: LectureSummary(
            mainTheme: "Patience during hardship",
            keyPoints: [
                "Trials are a test",
                "Remain patient and grateful"
            ],
            explicitAyatOrHadith: [
                "Indeed, Allah is with the patient."
            ],
            weeklyActions: ["Check in on your family this week"]
        ),
        audioPath: nil
    )
}

struct LectureSummary: Identifiable, Hashable, Codable {
    var id: String { mainTheme + keyPoints.joined() }
    var mainTheme: String
    var keyPoints: [String]
    var explicitAyatOrHadith: [String]
    var weeklyActions: [String]
}
