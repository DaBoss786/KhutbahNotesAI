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
    case summarizing
    case transcribed
    case ready
    case failed
    case blockedQuota
}

struct Lecture: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date
    var durationMinutes: Int?
    var chargedMinutes: Int?
    var isFavorite: Bool
    var status: LectureStatus
    var quotaReason: String?
    var transcript: String?
    var summary: LectureSummary?
    var audioPath: String?
    var folderId: String?
    var folderName: String?
}

extension Lecture {
    static let mock = Lecture(
        id: "mock-1",
        title: "Tafseer of Surah Al-Kahf",
        date: Date(),
        durationMinutes: 45,
        chargedMinutes: 45,
        isFavorite: true,
        status: .ready,
        quotaReason: nil,
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
        audioPath: nil,
        folderId: nil,
        folderName: nil
    )
}

struct LectureSummary: Identifiable, Hashable, Codable {
    var id: String { mainTheme + keyPoints.joined() }
    var mainTheme: String
    var keyPoints: [String]
    var explicitAyatOrHadith: [String]
    var weeklyActions: [String]
}

struct Folder: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var createdAt: Date
}
