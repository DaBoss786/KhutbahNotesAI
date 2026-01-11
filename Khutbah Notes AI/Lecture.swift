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

struct SummaryInProgressState: Hashable, Codable {
    var startedAt: Date?
    var expiresAt: Date?
    var isLegacy: Bool
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
    var errorMessage: String? = nil
    var transcript: String?
    var transcriptFormatted: String?
    var notes: String? = nil
    var summary: LectureSummary?
    var summaryInProgress: SummaryInProgressState? = nil
    var summaryTranslations: [SummaryTranslation]? = nil
    var summaryTranslationRequests: [String] = []
    var summaryTranslationInProgress: [String] = []
    var summaryTranslationErrors: [SummaryTranslationError]? = nil
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
        transcriptFormatted: "Sample transcript...",
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

    var isDemo: Bool {
        id == "demo-welcome" || (audioPath?.hasPrefix("demo/") ?? false)
    }
}

extension Lecture {
    static let summaryRetryTTL: TimeInterval = 15 * 60
    
    var hasTranscript: Bool {
        let trimmed = transcript?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        return !trimmed.isEmpty
    }
    
    func shouldShowSummaryRetry(now: Date = Date()) -> Bool {
        guard summary == nil else { return false }
        
        if status == .failed {
            return hasTranscript
        }
        
        guard status == .summarizing else { return false }
        guard let inProgress = summaryInProgress else { return false }
        
        if let expiresAt = inProgress.expiresAt {
            return now >= expiresAt
        }
        
        if let startedAt = inProgress.startedAt {
            return now.timeIntervalSince(startedAt) >= Self.summaryRetryTTL
        }
        
        return false
    }
}

struct LectureSummary: Identifiable, Hashable, Codable {
    var id: String { mainTheme + keyPoints.joined() }
    var mainTheme: String
    var keyPoints: [String]
    var explicitAyatOrHadith: [String]
    var weeklyActions: [String]
}

enum SummaryTranslationLanguage: String, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case arabic = "ar"
    case urdu = "ur"
    case french = "fr"
    case turkish = "tr"
    case indonesian = "id"
    case malay = "ms"
    case spanish = "es"
    case bengali = "bn"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .english: return "English"
        case .arabic: return "Arabic"
        case .urdu: return "Urdu"
        case .french: return "French"
        case .turkish: return "Turkish"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        case .spanish: return "Spanish"
        case .bengali: return "Bengali"
        }
    }
    
    var isRTL: Bool {
        switch self {
        case .arabic, .urdu:
            return true
        default:
            return false
        }
    }
    
    static let displayOrder: [SummaryTranslationLanguage] = [
        .english,
        .arabic,
        .urdu,
        .french,
        .turkish,
        .indonesian,
        .malay,
        .spanish,
        .bengali
    ]
}

struct SummaryTranslation: Identifiable, Hashable, Codable {
    var id: String { languageCode }
    var languageCode: String
    var summary: LectureSummary
}

struct SummaryTranslationError: Identifiable, Hashable, Codable {
    var id: String { languageCode }
    var languageCode: String
    var message: String
}

struct Folder: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var createdAt: Date
}
