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
    var summary: String?
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
        summary: "Key lessons and reminders summarized for quick review."
    )
}
