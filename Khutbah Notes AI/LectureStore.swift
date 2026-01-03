import Foundation
import SwiftUI
import Combine
import AVFoundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage

private enum DemoLectureSeed {
    static let id = "demo-welcome"
    static let title = "Welcome to Khutbah Notes!"
    static let audioPath = "demo/Sample Lecture.mp3"
    static let transcript = """
    Assalamu alaikum wa rahmatullahi wa barakatuh.

    Think back to the last khutbah or lecture you attended, the words that stirred your heart, reminders that felt deeply relevant in that moment. Yet by the time the week unfolds, many of those reflections begin to fade.

    Khutbah Notes exists for those moments.

    As the khutbah is delivered, the app quietly records the lecture, capturing it word for word. It then organizes the message into clear summaries, key reminders, and actionable takeaways you can return to later or pass on to your friends and family.

    Whether it's a Jumu'ah khutbah, a weekly halaqah, or a special lecture, Khutbah Notes helps highlight what matters most: Qur'anic references, prophetic teachings, and central themes meant to guide daily life.

    Our goal is simple - to help you remember, reflect, and act upon what you hear, long after leaving the masjid.

    Khutbah Notes is not a replacement for the khutbah or the scholar delivering it. It is a quiet companion, helping preserve reminders that were meant to stay with you.

    JazakumAllahu khayran for listening. May Allah allow us to benefit from what we hear, act upon it sincerely, and carry its lessons into our lives.
    """
    static let summaryMainTheme = """
    The lecture centers on the challenge of retaining and applying spiritual reminders after attending khutbahs and Islamic lectures. While these messages often feel powerful and personally relevant in the moment, they are easily forgotten as the distractions and responsibilities of daily life take over. Khutbah Notes is presented as a supportive tool designed to help bridge this gap, preserving important reminders so they can continue to guide reflection and action beyond the masjid.
    """
    static let summaryKeyPoints = [
        "Spiritual reminders delivered during khutbahs and lectures frequently resonate deeply at the time but fade as the week progresses.",
        "Khutbah Notes is designed to quietly and respectfully record lectures without disrupting the experience.",
        "The app organizes spoken content into structured summaries, key reminders, and clear takeaways, making it easier to revisit later.",
        "It helps highlight essential elements of the message, including Qur'anic verses, prophetic teachings, and overarching themes relevant to daily life.",
        "The app is not meant to replace the khutbah or the scholar, but to serve as a companion that preserves and reinforces the message.",
        "By making reminders accessible after the lecture, Khutbah Notes encourages ongoing reflection and deeper engagement with Islamic teachings."
    ]
    static let summaryWeeklyActions = [
        "Revisit summarized khutbah notes at least once during the week to refresh key reminders.",
        "Reflect on how the main themes apply to personal behavior, intentions, and daily decisions.",
        "Choose one actionable takeaway from the lecture and consciously apply it in the coming days.",
        "Share a meaningful reminder or insight with family or friends to reinforce learning and encourage discussion.",
        "Use the preserved notes as a reference for personal reflection, journaling, or preparation for future discussions or halaqahs."
    ]
}

@MainActor
final class LectureStore: ObservableObject {
    @Published var lectures: [Lecture] = []
    @Published var folders: [Folder] = []
    @Published var userUsage: UserUsage?
    @Published private(set) var hasLoadedLectures = false
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
    private var folderListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private(set) var userId: String?
    private var durationFetches: Set<String> = []
    private let uploadFailureMessage = "Upload failed - tap to retry"
    private let uploadRetryDelays: [TimeInterval] = [1, 3, 9]
    private let maxUploadAttempts = 3
    private let maxUploadFileSizeBytes: Int64 = 100 * 1024 * 1024
    private let transcriptionBackend = "internal"
    private let summarizationBackend = "internal"
    private let supportedAudioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "m4b", "aif", "aiff", "caf"
    ]
    private let pendingRecordingStore = PendingRecordingStore()
    private var pendingUploads: [String: PendingUpload] = [:]
    private var uploadAnalytics: [String: UploadAnalyticsContext] = [:]
    private var transcriptionAnalytics: [String: TranscriptionAnalyticsContext] = [:]
    private var summarizationAnalytics: [String: SummarizationAnalyticsContext] = [:]
    private var transcriptionCorrelation: [String: TranscriptionCorrelationContext] = [:]
    @Published private(set) var activeUploads: Set<String> = []
    
    init(seedMockData: Bool = false) {
        if seedMockData {
            addMockData()
        }
    }
    
    func addMockData() {
        let today = Date()
        let calendar = Calendar.current
        
        lectures = [
            Lecture(
                id: "mock-1",
                title: "Tafseer of Surah Al-Kahf",
                date: today,
                durationMinutes: 45,
                chargedMinutes: 45,
                isFavorite: true,
                status: .ready,
                quotaReason: nil,
                transcript: nil,
                transcriptFormatted: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            ),
            Lecture(
                id: "mock-2",
                title: "Understanding Taqwa",
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                durationMinutes: 32,
                chargedMinutes: 32,
                isFavorite: false,
                status: .processing,
                quotaReason: nil,
                transcript: nil,
                transcriptFormatted: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            ),
            Lecture(
                id: "mock-3",
                title: "Mercy and Patience",
                date: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                durationMinutes: nil,
                chargedMinutes: nil,
                isFavorite: false,
                status: .failed,
                quotaReason: nil,
                transcript: nil,
                transcriptFormatted: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            )
        ]
    }
    
    func updateLecture(_ lecture: Lecture) {
        guard let index = lectures.firstIndex(where: { $0.id == lecture.id }) else { return }
        lectures[index] = lecture
    }

    var uploadFailureMessageText: String {
        uploadFailureMessage
    }
    
    private func startUploadAnalytics(
        lectureId: String,
        trigger: AudioUploadTrigger,
        fileURL: URL
    ) {
        let uploadId = UUID().uuidString
        let fileSizeBytes = fileSizeBytes(at: fileURL)
        let fileDurationSeconds = fileDurationSeconds(for: fileURL)
        let context = UploadAnalyticsContext(
            uploadId: uploadId,
            trigger: trigger,
            fileSizeBytes: fileSizeBytes,
            fileDurationSeconds: fileDurationSeconds,
            uploadStart: nil
        )
        uploadAnalytics[lectureId] = context
        AnalyticsManager.logAudioUploadAttempt(
            uploadId: uploadId,
            fileSizeBytes: fileSizeBytes,
            fileDurationSeconds: fileDurationSeconds,
            networkType: currentNetworkTypeValue(),
            trigger: trigger
        )
    }
    
    private func ensureUploadAnalyticsContext(
        lectureId: String,
        trigger: AudioUploadTrigger,
        fileURL: URL
    ) -> UploadAnalyticsContext {
        if let existing = uploadAnalytics[lectureId] {
            return existing
        }
        startUploadAnalytics(lectureId: lectureId, trigger: trigger, fileURL: fileURL)
        if let created = uploadAnalytics[lectureId] {
            return created
        }
        return UploadAnalyticsContext(
            uploadId: UUID().uuidString,
            trigger: trigger,
            fileSizeBytes: nil,
            fileDurationSeconds: nil,
            uploadStart: nil
        )
    }
    
    private func logUploadStarted(
        lectureId: String,
        trigger: AudioUploadTrigger,
        fileURL: URL,
        resume: Bool
    ) -> UploadAnalyticsContext {
        var context = ensureUploadAnalyticsContext(
            lectureId: lectureId,
            trigger: trigger,
            fileURL: fileURL
        )
        if context.uploadStart == nil {
            context.uploadStart = Date()
            uploadAnalytics[lectureId] = context
        }
        AnalyticsManager.logAudioUploadStarted(uploadId: context.uploadId, resume: resume)
        return context
    }
    
    private func logUploadFailure(
        lectureId: String,
        stage: AudioUploadFailureStage,
        errorCode: AudioUploadErrorCode,
        retryable: Bool
    ) {
        let uploadId = uploadAnalytics[lectureId]?.uploadId ?? UUID().uuidString
        AnalyticsManager.logAudioUploadFailed(
            uploadId: uploadId,
            failureStage: stage,
            errorCode: errorCode,
            networkType: currentNetworkTypeValue(),
            retryable: retryable
        )
        uploadAnalytics.removeValue(forKey: lectureId)
    }
    
    private func logUploadSuccess(
        lectureId: String,
        completion: UploadCompletionContext
    ) {
        let durationMs = Int((Date().timeIntervalSince(completion.uploadStartTime) * 1000).rounded())
        AnalyticsManager.logAudioUploadSuccess(
            uploadId: completion.uploadId,
            totalBytes: completion.totalBytes,
            durationMs: durationMs,
            retriesCount: completion.retriesCount
        )
        uploadAnalytics.removeValue(forKey: lectureId)
    }
    
    @discardableResult
    private func startTranscriptionAnalytics(
        lectureId: String,
        uploadId: String?,
        fileSizeBytes: Int64?,
        fileDurationSeconds: Int?,
        trigger: TranscriptionTrigger,
        languageHint: String?
    ) -> TranscriptionAnalyticsContext {
        if let existing = transcriptionAnalytics[lectureId] {
            return existing
        }
        let context = TranscriptionAnalyticsContext(
            transcriptionId: UUID().uuidString,
            uploadId: uploadId,
            audioSizeBytes: fileSizeBytes,
            audioDurationSeconds: fileDurationSeconds,
            trigger: trigger,
            languageHint: languageHint,
            requestStart: Date(),
            requestSent: false,
            retriesCount: 0
        )
        transcriptionAnalytics[lectureId] = context
        transcriptionCorrelation[lectureId] = TranscriptionCorrelationContext(
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId
        )
        AnalyticsManager.logTranscriptionRequestAttempt(
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            audioDurationSeconds: context.audioDurationSeconds,
            audioSizeBytes: context.audioSizeBytes,
            networkType: currentNetworkTypeValue(),
            trigger: trigger,
            languageHint: context.languageHint
        )
        return context
    }
    
    private func logTranscriptionRequestSent(lectureId: String) {
        guard var context = transcriptionAnalytics[lectureId], !context.requestSent else {
            return
        }
        // Use audio size as a proxy for request payload size.
        AnalyticsManager.logTranscriptionRequestSent(
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            backend: transcriptionBackend,
            requestBytes: context.audioSizeBytes
        )
        context.requestSent = true
        transcriptionAnalytics[lectureId] = context
    }
    
    private func logTranscriptionFailure(
        lectureId: String,
        stage: TranscriptionFailureStage,
        errorCode: TranscriptionErrorCode,
        httpStatus: Int?,
        retryable: Bool
    ) {
        guard let context = transcriptionAnalytics[lectureId] else { return }
        AnalyticsManager.logTranscriptionFailed(
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            failureStage: stage,
            errorCode: errorCode,
            httpStatus: httpStatus,
            retryable: retryable,
            networkType: currentNetworkTypeValue()
        )
        transcriptionAnalytics.removeValue(forKey: lectureId)
    }
    
    private func logTranscriptionSuccess(
        lectureId: String,
        transcript: String?
    ) {
        guard let context = transcriptionAnalytics[lectureId] else { return }
        let processingMs: Int?
        if let requestStart = context.requestStart {
            processingMs = Int((Date().timeIntervalSince(requestStart) * 1000).rounded())
        } else {
            processingMs = nil
        }
        AnalyticsManager.logTranscriptionSuccess(
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            transcriptChars: transcript?.count,
            processingMs: processingMs,
            retriesCount: context.retriesCount
        )
        transcriptionAnalytics.removeValue(forKey: lectureId)
    }

    @discardableResult
    private func startSummarizationAnalytics(
        lecture: Lecture,
        trigger: SummarizationTrigger,
        startedAt: Date?
    ) -> SummarizationAnalyticsContext {
        if let existing = summarizationAnalytics[lecture.id] {
            return existing
        }
        let transcriptText = lecture.transcript ?? lecture.transcriptFormatted
        let transcriptChars = transcriptText?.count
        let transcriptBytes = transcriptText.map { Int64($0.utf8.count) }
        let correlation = summarizationCorrelation(for: lecture.id)
        let context = SummarizationAnalyticsContext(
            summarizationId: UUID().uuidString,
            transcriptionId: correlation?.transcriptionId,
            uploadId: correlation?.uploadId,
            transcriptChars: transcriptChars,
            transcriptBytes: transcriptBytes,
            language: currentLanguageHintValue(),
            requestStart: startedAt ?? Date(),
            requestSent: false,
            retriesCount: 0
        )
        summarizationAnalytics[lecture.id] = context
        AnalyticsManager.logSummarizationRequestAttempt(
            summarizationId: context.summarizationId,
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            transcriptChars: context.transcriptChars,
            language: context.language,
            networkType: currentNetworkTypeValue(),
            trigger: trigger
        )
        return context
    }

    private func logSummarizationRequestSent(lectureId: String) {
        guard var context = summarizationAnalytics[lectureId], !context.requestSent else {
            return
        }
        AnalyticsManager.logSummarizationRequestSent(
            summarizationId: context.summarizationId,
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            backend: summarizationBackend,
            requestBytes: context.transcriptBytes
        )
        context.requestSent = true
        summarizationAnalytics[lectureId] = context
    }

    private func logSummarizationFailure(
        lectureId: String,
        stage: SummarizationFailureStage,
        errorCode: SummarizationErrorCode,
        httpStatus: Int?,
        retryable: Bool
    ) {
        guard let context = summarizationAnalytics[lectureId] else { return }
        AnalyticsManager.logSummarizationFailed(
            summarizationId: context.summarizationId,
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            failureStage: stage,
            errorCode: errorCode,
            httpStatus: httpStatus,
            retryable: retryable,
            networkType: currentNetworkTypeValue()
        )
        summarizationAnalytics.removeValue(forKey: lectureId)
    }

    private func logSummarizationSuccess(
        lectureId: String,
        summary: LectureSummary?
    ) {
        guard let context = summarizationAnalytics[lectureId] else { return }
        let processingMs: Int?
        if let requestStart = context.requestStart {
            processingMs = Int((Date().timeIntervalSince(requestStart) * 1000).rounded())
        } else {
            processingMs = nil
        }
        AnalyticsManager.logSummarizationSuccess(
            summarizationId: context.summarizationId,
            transcriptionId: context.transcriptionId,
            uploadId: context.uploadId,
            summaryChars: summaryCharCount(summary),
            processingMs: processingMs,
            retriesCount: context.retriesCount
        )
        summarizationAnalytics.removeValue(forKey: lectureId)
        transcriptionCorrelation.removeValue(forKey: lectureId)
    }
    
    private func handleTranscriptionAnalyticsUpdates(
        previousById: [String: Lecture],
        currentLectures: [Lecture]
    ) {
        for lecture in currentLectures {
            guard transcriptionAnalytics[lecture.id] != nil else { continue }
            let previous = previousById[lecture.id]
            if lecture.hasTranscript && (previous?.hasTranscript != true) {
                logTranscriptionSuccess(lectureId: lecture.id, transcript: lecture.transcript)
                continue
            }
            if lecture.status == .failed || lecture.status == .blockedQuota {
                let errorCode: TranscriptionErrorCode = lecture.status == .blockedQuota ? .quota : .unknown
                logTranscriptionFailure(
                    lectureId: lecture.id,
                    stage: .processing,
                    errorCode: errorCode,
                    httpStatus: nil,
                    retryable: isRetryable(errorCode: errorCode)
                )
            }
        }
    }

    private func handleSummarizationAnalyticsUpdates(
        previousById: [String: Lecture],
        currentLectures: [Lecture]
    ) {
        for lecture in currentLectures {
            let previous = previousById[lecture.id]
            if let startedAt = lecture.summaryInProgress?.startedAt,
               var context = summarizationAnalytics[lecture.id] {
                context.requestStart = startedAt
                summarizationAnalytics[lecture.id] = context
            }
            let isSummarizing = lecture.status == .summarizing || lecture.summaryInProgress != nil
            let wasSummarizing = previous?.status == .summarizing || previous?.summaryInProgress != nil
            if isSummarizing && !wasSummarizing {
                _ = startSummarizationAnalytics(
                    lecture: lecture,
                    trigger: .auto,
                    startedAt: lecture.summaryInProgress?.startedAt
                )
                logSummarizationRequestSent(lectureId: lecture.id)
            } else if isSummarizing {
                logSummarizationRequestSent(lectureId: lecture.id)
            }
            if lecture.summary != nil && (previous?.summary == nil) {
                logSummarizationSuccess(lectureId: lecture.id, summary: lecture.summary)
                continue
            }
            if lecture.status == .failed || lecture.status == .blockedQuota {
                let errorCode: SummarizationErrorCode = lecture.status == .blockedQuota ? .quota : .unknown
                logSummarizationFailure(
                    lectureId: lecture.id,
                    stage: .processing,
                    errorCode: errorCode,
                    httpStatus: nil,
                    retryable: isRetryable(errorCode: errorCode)
                )
            }
        }
    }

    private func summarizationCorrelation(
        for lectureId: String
    ) -> TranscriptionCorrelationContext? {
        if let active = transcriptionAnalytics[lectureId] {
            return TranscriptionCorrelationContext(
                transcriptionId: active.transcriptionId,
                uploadId: active.uploadId
            )
        }
        return transcriptionCorrelation[lectureId]
    }

    private func summaryCharCount(_ summary: LectureSummary?) -> Int? {
        guard let summary else { return nil }
        var count = summary.mainTheme.count
        for point in summary.keyPoints {
            count += point.count
        }
        for item in summary.explicitAyatOrHadith {
            count += item.count
        }
        for action in summary.weeklyActions {
            count += action.count
        }
        return count
    }
    
    private func currentNetworkTypeValue() -> String {
        NetworkTypeProvider.shared.currentNetworkType().rawValue
    }
    
    private func currentLanguageHintValue() -> String? {
        Locale.current.languageCode
    }
    
    private func transcriptionTrigger(for uploadTrigger: AudioUploadTrigger) -> TranscriptionTrigger {
        switch uploadTrigger {
        case .manual:
            return .manual
        case .recording, .retake:
            return .auto
        }
    }
    
    private func normalizedUploadErrorCode(_ error: Error) -> AudioUploadErrorCode {
        if let prepError = error as? AudioUploadPreparationError {
            switch prepError {
            case .fileTooLarge:
                return .fileTooLarge
            case .unsupportedFileType, .unreadable, .transcodeFailed:
                return .client4xx
            }
        }
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut {
                return .timeout
            }
            if nsError.code == NSURLErrorCancelled {
                return .canceled
            }
            return .network
        }
        
        if nsError.domain == StorageErrorDomain,
           let code = StorageErrorCode(rawValue: nsError.code) {
            switch code {
            case .unauthenticated, .unauthorized:
                return .auth
            case .cancelled:
                return .canceled
            case .retryLimitExceeded:
                return .network
            case .quotaExceeded:
                return .client4xx
            case .unknown:
                return .unknown
            default:
                return .unknown
            }
        }
        
        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .unauthenticated, .permissionDenied:
                return .auth
            case .deadlineExceeded:
                return .timeout
            case .unavailable:
                return .network
            case .resourceExhausted, .failedPrecondition, .invalidArgument:
                return .client4xx
            default:
                return .unknown
            }
        }
        
        return .unknown
    }
    
    private func isRetryable(errorCode: AudioUploadErrorCode) -> Bool {
        switch errorCode {
        case .network, .timeout, .server5xx:
            return true
        default:
            return false
        }
    }
    
    private func normalizedTranscriptionErrorCode(_ error: Error) -> TranscriptionErrorCode {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut {
                return .timeout
            }
            if nsError.code == NSURLErrorCancelled {
                return .canceled
            }
            return .network
        }
        
        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .unauthenticated, .permissionDenied:
                return .auth
            case .deadlineExceeded:
                return .timeout
            case .unavailable:
                return .network
            case .resourceExhausted:
                return .quota
            case .invalidArgument, .failedPrecondition:
                return .client4xx
            default:
                return .unknown
            }
        }
        
        return .unknown
    }
    
    private func isRetryable(errorCode: TranscriptionErrorCode) -> Bool {
        switch errorCode {
        case .network, .timeout, .server5xx:
            return true
        default:
            return false
        }
    }

    private func normalizedSummarizationErrorCode(_ error: Error) -> SummarizationErrorCode {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut {
                return .timeout
            }
            if nsError.code == NSURLErrorCancelled {
                return .canceled
            }
            return .network
        }

        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .unauthenticated, .permissionDenied:
                return .auth
            case .deadlineExceeded:
                return .timeout
            case .unavailable:
                return .network
            case .resourceExhausted:
                return .quota
            case .invalidArgument, .outOfRange:
                return .invalidInput
            case .failedPrecondition, .alreadyExists, .notFound:
                return .client4xx
            case .cancelled:
                return .canceled
            default:
                return .unknown
            }
        }

        return .unknown
    }

    private func isRetryable(errorCode: SummarizationErrorCode) -> Bool {
        switch errorCode {
        case .network, .timeout, .server5xx:
            return true
        default:
            return false
        }
    }

    func requestSummaryTranslation(
        for lecture: Lecture,
        language: SummaryTranslationLanguage
    ) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot request translation.")
            return
        }
        
        let requestPath = FieldPath(["summaryTranslationRequests", language.rawValue])
        let errorPath = FieldPath(["summaryTranslationErrors", language.rawValue])
        let data: [AnyHashable: Any] = [
            requestPath: true,
            errorPath: FieldValue.delete(),
        ]
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("lectures")
                .document(lecture.id)
                .updateData(data)
        } catch {
            print("Failed to request summary translation: \(error.localizedDescription)")
        }
    }

    func retrySummary(for lecture: Lecture) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot retry summary.")
            return
        }
        
        guard lecture.summary == nil else { return }
        summarizationAnalytics.removeValue(forKey: lecture.id)
        _ = startSummarizationAnalytics(
            lecture: lecture,
            trigger: .manual,
            startedAt: Date()
        )
        
        let data: [String: Any] = [
            "status": "transcribed",
            "summaryInProgress": FieldValue.delete(),
            "errorMessage": FieldValue.delete()
        ]
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("lectures")
                .document(lecture.id)
                .updateData(data)
            logSummarizationRequestSent(lectureId: lecture.id)
        } catch {
            let errorCode = normalizedSummarizationErrorCode(error)
            logSummarizationFailure(
                lectureId: lecture.id,
                stage: .request,
                errorCode: errorCode,
                httpStatus: nil,
                retryable: isRetryable(errorCode: errorCode)
            )
            print("Failed to retry summary: \(error.localizedDescription)")
        }
    }
    
    func saveJumuahStartTime(_ time: String, timezoneIdentifier: String) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot save Jumu'ah start time.")
            return
        }
        
        let data: [String: Any] = [
            "preferences": [
                "jumuahStartTime": time,
                "jumuahTimezone": timezoneIdentifier
            ]
        ]
        
        do {
            try await db.collection("users").document(userId).setData(data, merge: true)
            try await removeLegacyPreferenceDotFields(keys: ["jumuahStartTime", "jumuahTimezone"])
            print("Saved Jumu'ah start time for user \(userId): \(time) (\(timezoneIdentifier))")
        } catch {
            print("Failed to save Jumu'ah start time: \(error.localizedDescription)")
        }
    }
    
    func saveNotificationPreference(_ preference: String) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot save notification preference.")
            return
        }
        
        let data: [String: Any] = [
            "preferences": [
                "notificationPreference": preference
            ]
        ]
        
        do {
            try await db.collection("users").document(userId).setData(data, merge: true)
            try await removeLegacyPreferenceDotFields(keys: ["notificationPreference"])
            print("Saved notification preference for user \(userId): \(preference)")
        } catch {
            print("Failed to save notification preference: \(error.localizedDescription)")
        }
    }

    func submitFeedback(email: String, message: String) async throws {
        guard let userId else {
            throw FeedbackError.missingUserId
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw FeedbackError.missingEmail
        }
        var data: [String: Any] = [
            "email": trimmedEmail,
            "message": message,
            "userId": userId,
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await db.collection("feedback").addDocument(data: data)
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionError.missingUser
        }

        let token = try await fetchIdToken(for: user)
        let url = try deleteAccountURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw AccountDeletionError.requestFailed(message)
        }

        resetLocalState()
        try? Auth.auth().signOut()
        await startAnonymousSessionIfPossible()
    }

    private func deleteAccountURL() throws -> URL {
        guard let projectId = FirebaseApp.app()?.options.projectID else {
            throw AccountDeletionError.missingProjectId
        }

        let urlString = "https://us-central1-\(projectId).cloudfunctions.net/deleteAccount"
        guard let url = URL(string: urlString) else {
            throw AccountDeletionError.invalidURL
        }
        return url
    }

    private func fetchIdToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AccountDeletionError.missingAuthToken)
                }
            }
        }
    }

    private func resetLocalState() {
        listener?.remove()
        folderListener?.remove()
        userListener?.remove()
        listener = nil
        folderListener = nil
        userListener = nil
        lectures = []
        folders = []
        userUsage = nil
        userId = nil
        durationFetches.removeAll()
    }

    private func startAnonymousSessionIfPossible() async {
        do {
            let result = try await signInAnonymously()
            await MainActor.run {
                self.start(for: result.user.uid)
            }
        } catch {
            print("Failed to start a new session after deletion: \(error.localizedDescription)")
        }
    }

    private func signInAnonymously() async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AccountDeletionError.signInFailed)
                }
            }
        }
    }
    
    private func removeLegacyPreferenceDotFields(keys: [String]) async throws {
        guard let userId else { return }
        var deletes: [String: Any] = [:]
        keys.forEach { key in
            deletes["preferences.\(key)"] = FieldValue.delete()
        }
        if !deletes.isEmpty {
            try await db.collection("users").document(userId).setData(deletes, merge: true)
        }
    }
    
    func start(for userId: String) {
        self.userId = userId
        hasLoadedLectures = false
        restorePendingRecordings(for: userId)
        resumePendingUploads()
        
        // Stop any previous listener
        listener?.remove()
        folderListener?.remove()
        userListener?.remove()
        
        // Listen to this user's lectures collection
        listener = db.collection("users")
            .document(userId)
            .collection("lectures")
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to lectures: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.lectures = []
                    self.hasLoadedLectures = true
                    return
                }
                
                var previousById: [String: Lecture] = [:]
                previousById.reserveCapacity(self.lectures.count)
                for lecture in self.lectures {
                    previousById[lecture.id] = lecture
                }
                let updatedLectures: [Lecture] = documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    
                    guard let title = data["title"] as? String,
                          let timestamp = data["date"] as? Timestamp,
                          let statusString = data["status"] as? String else {
                        return nil
                    }
                    
                    let date = timestamp.dateValue()
                    let durationMinutes = data["durationMinutes"] as? Int
                    let chargedMinutes = data["chargedMinutes"] as? Int
                    let isFavorite = data["isFavorite"] as? Bool ?? false
                    let transcript = data["transcript"] as? String
                    let transcriptFormatted = data["transcriptFormatted"] as? String
                    let audioPath = data["audioPath"] as? String
                    let folderId = data["folderId"] as? String
                    let folderName = data["folderName"] as? String
                    let quotaReason = data["quotaReason"] as? String
                    let errorMessage = data["errorMessage"] as? String
                    
                    let summary = LectureSummaryParser.parseSummary(
                        from: data["summary"] as? [String: Any]
                    )
                    let summaryInProgress = LectureSummaryParser.parseSummaryInProgress(
                        from: data["summaryInProgress"]
                    )
                    let summaryTranslations = LectureSummaryParser.parseSummaryTranslations(
                        from: data["summaryTranslations"] as? [String: Any]
                    )
                    let translationRequests = LectureSummaryParser.translationKeys(
                        from: data["summaryTranslationRequests"]
                    )
                    let translationInProgress = LectureSummaryParser.translationKeys(
                        from: data["summaryTranslationInProgress"]
                    )
                    let translationErrors = LectureSummaryParser.parseTranslationErrors(
                        from: data["summaryTranslationErrors"] as? [String: Any]
                    )
                    
                    let status: LectureStatus
                    switch statusString {
                    case "recording": status = .recording
                    case "processing": status = .processing
                    case "summarizing": status = .summarizing
                    case "transcribed": status = .transcribed
                    case "ready": status = .ready
                    case "blocked_quota": status = .blockedQuota
                    case "failed": status = .failed
                    default: status = .processing
                    }
                    
                    return Lecture(
                        id: id,
                        title: title,
                        date: date,
                        durationMinutes: durationMinutes,
                        chargedMinutes: chargedMinutes,
                        isFavorite: isFavorite,
                        status: status,
                        quotaReason: quotaReason,
                        errorMessage: errorMessage,
                        transcript: transcript,
                        transcriptFormatted: transcriptFormatted,
                        summary: summary,
                        summaryInProgress: summaryInProgress,
                        summaryTranslations: summaryTranslations.isEmpty ?
                            nil :
                            summaryTranslations,
                        summaryTranslationRequests: translationRequests,
                        summaryTranslationInProgress: translationInProgress,
                        summaryTranslationErrors: translationErrors.isEmpty ?
                            nil :
                            translationErrors,
                        audioPath: audioPath,
                        folderId: folderId,
                        folderName: folderName
                    )
                }
                self.handleTranscriptionAnalyticsUpdates(
                    previousById: previousById,
                    currentLectures: updatedLectures
                )
                self.handleSummarizationAnalyticsUpdates(
                    previousById: previousById,
                    currentLectures: updatedLectures
                )
                self.lectures = self.mergePendingLectures(into: updatedLectures)
                self.fillMissingDurationsIfNeeded(for: updatedLectures)
                self.hasLoadedLectures = true
            }
        
        userListener = db.collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Error listening to user doc: \(error)")
                    return
                }
                guard let data = snapshot?.data() else { return }
                
                let plan = data["plan"] as? String ?? "free"
                let monthlyMinutesUsed = data["monthlyMinutesUsed"] as? Int ?? 0
                let monthlyKey = data["monthlyKey"] as? String
                let freeLifetimeMinutesUsed = data["freeLifetimeMinutesUsed"] as? Int ?? 0
                let freeLifetimeMinutesRemaining = data["freeLifetimeMinutesRemaining"] as? Int
                let periodStart = (data["periodStart"] as? Timestamp)?.dateValue()
                let renewsAt = (data["renewsAt"] as? Timestamp)?.dateValue()
                
                self.userUsage = UserUsage(
                    plan: plan,
                    monthlyMinutesUsed: monthlyMinutesUsed,
                    monthlyKey: monthlyKey,
                    freeLifetimeMinutesUsed: freeLifetimeMinutesUsed,
                    freeLifetimeMinutesRemaining: freeLifetimeMinutesRemaining,
                    periodStart: periodStart,
                    renewsAt: renewsAt
                )
            }
        
        // Listen to this user's folders collection
        folderListener = db.collection("users")
            .document(userId)
            .collection("folders")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    print("Error listening to folders: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.folders = []
                    return
                }
                
                self.folders = documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    guard let name = data["name"] as? String else { return nil }
                    
                    let createdAt: Date
                    if let ts = data["createdAt"] as? Timestamp {
                        createdAt = ts.dateValue()
                    } else {
                        createdAt = Date()
                    }
                    
                    return Folder(id: id, name: name, createdAt: createdAt)
                }
            }

        Task {
            await seedDemoLectureIfNeeded(for: userId)
        }
    }
    
    @discardableResult
    func createLecture(
        withTitle title: String,
        recordingURL: URL,
        onError: ((String) -> Void)? = nil
    ) -> String? {
        guard let userId = userId else {
            print("No userId set on LectureStore; cannot create lecture.")
            return nil
        }
        
        let lectureId = UUID().uuidString
        let now = Date()
        let audioPath = "audio/\(userId)/\(lectureId).m4a"
        let durationMinutes = durationMinutes(for: recordingURL)
        
        let pending = PendingRecording(
            id: lectureId,
            userId: userId,
            title: title,
            date: now,
            durationMinutes: durationMinutes,
            audioPath: audioPath,
            filePath: recordingURL.path,
            trigger: .recording
        )
        pendingUploads[lectureId] = PendingUpload(
            lectureId: lectureId,
            recording: pending,
            sourceURL: nil,
            preparedURL: recordingURL
        )
        pendingRecordingStore.upsert(pending)
        
        // Optimistically insert a local lecture while upload happens
        let newLecture = Lecture(
            id: lectureId,
            title: title,
            date: now,
            durationMinutes: durationMinutes,
            chargedMinutes: nil,
            isFavorite: false,
            status: .processing,
            quotaReason: nil,
            transcript: nil,
            transcriptFormatted: nil,
            summary: nil,
            audioPath: audioPath,
            folderId: nil,
            folderName: nil
        )
        
        // Insert at top so UI feels instant; Firestore listener will overwrite as needed
        lectures.insert(newLecture, at: 0)
        startUploadAnalytics(
            lectureId: lectureId,
            trigger: .recording,
            fileURL: recordingURL
        )
        Task { [weak self] in
            await self?.uploadLectureAudioWithRetry(
                lectureId: lectureId,
                title: title,
                recordingURL: recordingURL,
                audioPath: audioPath,
                date: now,
                durationMinutes: durationMinutes,
                trigger: .recording,
                resume: false,
                onError: onError
            )
        }
        return lectureId
    }

    @discardableResult
    func createLectureFromFile(
        withTitle title: String,
        fileURL: URL,
        onError: ((String) -> Void)? = nil
    ) -> String? {
        guard let userId = userId else {
            print("No userId set on LectureStore; cannot create lecture.")
            return nil
        }
        
        let lectureId = UUID().uuidString
        startUploadAnalytics(
            lectureId: lectureId,
            trigger: .manual,
            fileURL: fileURL
        )
        
        if let validationError = validatePickedAudioFile(at: fileURL) {
            let message = uploadPreparationMessage(for: validationError)
            let errorCode = normalizedUploadErrorCode(validationError)
            logUploadFailure(
                lectureId: lectureId,
                stage: .prepare,
                errorCode: errorCode,
                retryable: isRetryable(errorCode: errorCode)
            )
            onError?(message)
            return nil
        }
        
        let now = Date()
        let audioPath = "audio/\(userId)/\(lectureId).m4a"
        let durationMinutes = durationMinutes(for: fileURL)
        
        let newLecture = Lecture(
            id: lectureId,
            title: title,
            date: now,
            durationMinutes: durationMinutes,
            chargedMinutes: nil,
            isFavorite: false,
            status: .processing,
            quotaReason: nil,
            transcript: nil,
            transcriptFormatted: nil,
            summary: nil,
            audioPath: audioPath,
            folderId: nil,
            folderName: nil
        )
        
        lectures.insert(newLecture, at: 0)
        pendingUploads[lectureId] = PendingUpload(
            lectureId: lectureId,
            recording: nil,
            sourceURL: fileURL,
            preparedURL: nil
        )
        Task { [weak self] in
            await self?.uploadLectureFromFileWithRetry(
                lectureId: lectureId,
                title: title,
                sourceURL: fileURL,
                audioPath: audioPath,
                date: now,
                durationMinutes: durationMinutes,
                trigger: .manual,
                resume: false,
                onError: onError
            )
        }
        
        return lectureId
    }

    func retryLectureUpload(
        lectureId: String,
        onError: ((String) -> Void)? = nil
    ) {
        guard !activeUploads.contains(lectureId) else {
            print("Upload already in progress for lecture \(lectureId).")
            return
        }
        guard let lecture = lectures.first(where: { $0.id == lectureId }),
              let audioPath = lecture.audioPath else {
            print("Missing lecture metadata for retry upload \(lectureId).")
            return
        }

        if let pending = pendingUploads[lectureId] {
            if let recording = pending.recording {
                let recordingURL = pending.preparedURL ?? recording.fileURL
                if FileManager.default.fileExists(atPath: recordingURL.path) {
                    startUploadAnalytics(
                        lectureId: lectureId,
                        trigger: recording.trigger,
                        fileURL: recordingURL
                    )
                    Task { [weak self] in
                        await self?.uploadLectureAudioWithRetry(
                            lectureId: lectureId,
                            title: lecture.title,
                            recordingURL: recordingURL,
                            audioPath: audioPath,
                            date: lecture.date,
                            durationMinutes: lecture.durationMinutes,
                            trigger: recording.trigger,
                            resume: true,
                            onError: onError
                        )
                    }
                    return
                }
                clearPendingUpload(lectureId: lectureId)
            }
            
            if let preparedURL = pending.preparedURL {
                if FileManager.default.fileExists(atPath: preparedURL.path) {
                    startUploadAnalytics(
                        lectureId: lectureId,
                        trigger: .manual,
                        fileURL: preparedURL
                    )
                    Task { [weak self] in
                        await self?.uploadLectureAudioWithRetry(
                            lectureId: lectureId,
                            title: lecture.title,
                            recordingURL: preparedURL,
                            audioPath: audioPath,
                            date: lecture.date,
                            durationMinutes: lecture.durationMinutes,
                            trigger: .manual,
                            resume: true,
                            onError: onError
                        )
                    }
                    return
                }
            }
            
            if let sourceURL = pending.sourceURL {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    startUploadAnalytics(
                        lectureId: lectureId,
                        trigger: .manual,
                        fileURL: sourceURL
                    )
                    Task { [weak self] in
                        await self?.uploadLectureFromFileWithRetry(
                            lectureId: lectureId,
                            title: lecture.title,
                            sourceURL: sourceURL,
                            audioPath: audioPath,
                            date: lecture.date,
                            durationMinutes: lecture.durationMinutes,
                            trigger: .manual,
                            resume: true,
                            onError: onError
                        )
                    }
                    return
                }
            }
        }
        
        print("No pending recording URL found for lecture \(lectureId); cannot retry upload.")
    }

    private func uploadLectureFromFileWithRetry(
        lectureId: String,
        title: String,
        sourceURL: URL,
        audioPath: String,
        date: Date,
        durationMinutes: Int?,
        trigger: AudioUploadTrigger,
        resume: Bool,
        onError: ((String) -> Void)? = nil
    ) async {
        guard let userId = userId else {
            logUploadFailure(
                lectureId: lectureId,
                stage: .auth,
                errorCode: .auth,
                retryable: false
            )
            print("No userId set on LectureStore; cannot upload lecture.")
            return
        }
        guard !activeUploads.contains(lectureId) else {
            print("Upload already in progress for lecture \(lectureId).")
            return
        }
        
        _ = ensureUploadAnalyticsContext(
            lectureId: lectureId,
            trigger: trigger,
            fileURL: sourceURL
        )
        
        do {
            let prepared = try await prepareAudioFileForUpload(from: sourceURL, lectureId: lectureId)
            var pending = pendingUploads[lectureId] ?? PendingUpload(
                lectureId: lectureId,
                recording: nil,
                sourceURL: sourceURL,
                preparedURL: nil
            )
            pending.preparedURL = prepared.url
            pending.sourceURL = sourceURL
            pendingUploads[lectureId] = pending
            
            let resolvedDuration = prepared.durationMinutes ?? durationMinutes
            if let preparedDuration = prepared.durationMinutes, preparedDuration != durationMinutes {
                updateLocalLectureDuration(lectureId: lectureId, durationMinutes: preparedDuration)
            }
            
            await uploadLectureAudioWithRetry(
                lectureId: lectureId,
                title: title,
                recordingURL: prepared.url,
                audioPath: audioPath,
                date: date,
                durationMinutes: resolvedDuration,
                trigger: trigger,
                resume: resume,
                onError: onError
            )
        } catch {
            let message = uploadPreparationMessage(for: error)
            let shouldKeepSource = message == uploadFailureMessage
            
            if !shouldKeepSource {
                clearPendingUpload(lectureId: lectureId)
            }
            
            markUploadFailed(
                userId: userId,
                lectureId: lectureId,
                title: title,
                date: date,
                durationMinutes: durationMinutes,
                audioPath: audioPath,
                errorMessage: message
            )
            let errorCode = normalizedUploadErrorCode(error)
            logUploadFailure(
                lectureId: lectureId,
                stage: .prepare,
                errorCode: errorCode,
                retryable: isRetryable(errorCode: errorCode)
            )
            onError?(message)
        }
    }

    private func uploadLectureAudioWithRetry(
        lectureId: String,
        title: String,
        recordingURL: URL,
        audioPath: String,
        date: Date,
        durationMinutes: Int?,
        trigger: AudioUploadTrigger,
        resume: Bool,
        onError: ((String) -> Void)? = nil
    ) async {
        guard let userId = userId else {
            logUploadFailure(
                lectureId: lectureId,
                stage: .auth,
                errorCode: .auth,
                retryable: false
            )
            print("No userId set on LectureStore; cannot upload lecture.")
            return
        }
        guard !activeUploads.contains(lectureId) else {
            print("Upload already in progress for lecture \(lectureId).")
            return
        }
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            print("Recording file missing for lecture \(lectureId) at \(recordingURL.path).")
            if let pending = pendingUploads[lectureId] {
                if pending.recording != nil {
                    clearPendingUpload(lectureId: lectureId)
                } else if pending.sourceURL != nil {
                    var updated = pending
                    updated.preparedURL = nil
                    pendingUploads[lectureId] = updated
                } else {
                    clearPendingUpload(lectureId: lectureId)
                }
            }
            markUploadFailed(
                userId: userId,
                lectureId: lectureId,
                title: title,
                date: date,
                durationMinutes: durationMinutes,
                audioPath: audioPath
            )
            logUploadFailure(
                lectureId: lectureId,
                stage: .prepare,
                errorCode: .client4xx,
                retryable: false
            )
            onError?(uploadFailureMessage)
            return
        }
        
        activeUploads.insert(lectureId)
        defer { activeUploads.remove(lectureId) }
        
        let audioRef = storage.reference(withPath: audioPath)
        let uploadMetadata = StorageMetadata()
        uploadMetadata.contentType = "audio/m4a"
        
        let uploadContext = logUploadStarted(
            lectureId: lectureId,
            trigger: trigger,
            fileURL: recordingURL,
            resume: resume
        )
        let uploadStartTime = uploadContext.uploadStart ?? Date()
        let totalBytes = fileSizeBytes(at: recordingURL)
        
        for attempt in 1...maxUploadAttempts {
            print("Uploading audio for lecture \(lectureId) (attempt \(attempt)/\(maxUploadAttempts))")
            do {
                _ = try await putFileAsync(from: recordingURL, to: audioRef, metadata: uploadMetadata)
                clearPendingUpload(lectureId: lectureId)
                print("Upload succeeded for lecture \(lectureId).")
                updateLocalLectureStatus(lectureId: lectureId, status: .processing, errorMessage: nil)
                _ = startTranscriptionAnalytics(
                    lectureId: lectureId,
                    uploadId: uploadContext.uploadId,
                    fileSizeBytes: uploadContext.fileSizeBytes ?? totalBytes,
                    fileDurationSeconds: uploadContext.fileDurationSeconds,
                    trigger: transcriptionTrigger(for: trigger),
                    languageHint: currentLanguageHintValue()
                )
                saveLectureDocument(
                    userId: userId,
                    lectureId: lectureId,
                    title: title,
                    date: date,
                    durationMinutes: durationMinutes,
                    audioPath: audioPath,
                    status: "processing",
                    errorMessage: nil,
                    uploadCompletion: UploadCompletionContext(
                        uploadId: uploadContext.uploadId,
                        uploadStartTime: uploadStartTime,
                        totalBytes: totalBytes,
                        retriesCount: attempt - 1
                    ),
                    onError: onError
                )
                return
            } catch {
                let shouldRetry = isTransientUploadError(error) && attempt < maxUploadAttempts
                print("Upload attempt \(attempt) failed for lecture \(lectureId): \(error)")
                if shouldRetry {
                    let delay = uploadRetryDelays[min(attempt - 1, uploadRetryDelays.count - 1)]
                    print("Retrying upload for lecture \(lectureId) in \(delay)s.")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                print("Upload failed after \(attempt) attempts for lecture \(lectureId).")
                markUploadFailed(
                    userId: userId,
                    lectureId: lectureId,
                    title: title,
                    date: date,
                    durationMinutes: durationMinutes,
                    audioPath: audioPath
                )
                let errorCode = normalizedUploadErrorCode(error)
                logUploadFailure(
                    lectureId: lectureId,
                    stage: .upload,
                    errorCode: errorCode,
                    retryable: isTransientUploadError(error)
                )
                onError?(uploadFailureMessage)
                return
            }
        }
    }

    private func putFileAsync(
        from url: URL,
        to reference: StorageReference,
        metadata: StorageMetadata
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            reference.putFile(from: url, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "LectureStoreUpload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Upload failed with no metadata."]
                    ))
                }
            }
        }
    }

    private func saveLectureDocument(
        userId: String,
        lectureId: String,
        title: String,
        date: Date,
        durationMinutes: Int?,
        audioPath: String,
        status: String,
        errorMessage: String?,
        uploadCompletion: UploadCompletionContext? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        var docData: [String: Any] = [
            "title": title,
            "date": Timestamp(date: date),
            "isFavorite": false,
            "status": status,
            "transcript": NSNull(),
            "summary": NSNull(),
            "audioPath": audioPath
        ]
        docData["durationMinutes"] = durationMinutes ?? NSNull()
        if let errorMessage {
            docData["errorMessage"] = errorMessage
        } else {
            docData["errorMessage"] = FieldValue.delete()
        }
        
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lectureId)
            .setData(docData, merge: true) { error in
                if let error = error {
                    print("Error saving lecture doc: \(error)")
                    if let onError {
                        Task { @MainActor in
                            onError("Couldn't save lecture details. Please try again.")
                        }
                    }
                    Task { @MainActor in
                        if let uploadCompletion {
                            let errorCode = self.normalizedUploadErrorCode(error)
                            self.logUploadFailure(
                                lectureId: lectureId,
                                stage: .finalize,
                                errorCode: errorCode,
                                retryable: self.isRetryable(errorCode: errorCode)
                            )
                        }
                        let transcriptionError = self.normalizedTranscriptionErrorCode(error)
                        self.logTranscriptionFailure(
                            lectureId: lectureId,
                            stage: .request,
                            errorCode: transcriptionError,
                            httpStatus: nil,
                            retryable: self.isRetryable(errorCode: transcriptionError)
                        )
                    }
                } else {
                    print("Lecture metadata saved to Firestore for \(lectureId)")
                    Task { @MainActor in
                        if let uploadCompletion {
                            self.logUploadSuccess(lectureId: lectureId, completion: uploadCompletion)
                        }
                        self.logTranscriptionRequestSent(lectureId: lectureId)
                    }
                }
            }
    }

    private func markUploadFailed(
        userId: String,
        lectureId: String,
        title: String,
        date: Date,
        durationMinutes: Int?,
        audioPath: String,
        errorMessage: String? = nil
    ) {
        let message = errorMessage ?? uploadFailureMessage
        updateLocalLectureStatus(
            lectureId: lectureId,
            status: .failed,
            errorMessage: message
        )
        saveLectureDocument(
            userId: userId,
            lectureId: lectureId,
            title: title,
            date: date,
            durationMinutes: durationMinutes,
            audioPath: audioPath,
            status: "failed",
            errorMessage: message
        )
    }

    private func updateLocalLectureStatus(
        lectureId: String,
        status: LectureStatus,
        errorMessage: String?
    ) {
        guard let index = lectures.firstIndex(where: { $0.id == lectureId }) else { return }
        var updated = lectures[index]
        updated.status = status
        updated.errorMessage = errorMessage
        lectures[index] = updated
    }

    private func updateLocalLectureDuration(lectureId: String, durationMinutes: Int?) {
        guard let index = lectures.firstIndex(where: { $0.id == lectureId }) else { return }
        var updated = lectures[index]
        updated.durationMinutes = durationMinutes
        lectures[index] = updated
    }

    private func isTransientUploadError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        if nsError.domain == StorageErrorDomain,
           let code = StorageErrorCode(rawValue: nsError.code) {
            switch code {
            case .unknown, .retryLimitExceeded:
                return true
            default:
                return false
            }
        }
        return false
    }

    nonisolated static func audioUploadValidationError(
        fileExtension: String,
        fileSizeBytes: Int64?,
        supportedExtensions: Set<String>,
        maxFileSizeBytes: Int64
    ) -> AudioUploadPreparationError? {
        let normalizedExtension = fileExtension.lowercased()
        guard supportedExtensions.contains(normalizedExtension) else {
            return .unsupportedFileType
        }
        if let sizeBytes = fileSizeBytes, sizeBytes > maxFileSizeBytes {
            return .fileTooLarge
        }
        return nil
    }

    private func validatePickedAudioFile(at url: URL) -> AudioUploadPreparationError? {
        Self.audioUploadValidationError(
            fileExtension: url.pathExtension,
            fileSizeBytes: fileSizeBytes(at: url),
            supportedExtensions: supportedAudioExtensions,
            maxFileSizeBytes: maxUploadFileSizeBytes
        )
    }

    private func fileSizeBytes(at url: URL) -> Int64? {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           values.isRegularFile == true,
           let size = values.fileSize {
            return Int64(size)
        }
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        
        return nil
    }

    private func uploadPreparationMessage(for error: Error) -> String {
        if let prepError = error as? AudioUploadPreparationError {
            switch prepError {
            case .unsupportedFileType:
                return unsupportedAudioTypeMessage
            case .fileTooLarge:
                return fileTooLargeMessage
            case .unreadable:
                return uploadFailureMessage
            case .transcodeFailed:
                return "Couldn't convert this file to M4A. Please choose another audio file."
            }
        }
        return uploadFailureMessage
    }

    private var unsupportedAudioTypeMessage: String {
        "Unsupported file type. Please choose a .m4a, .mp3, .wav, .aac, .m4b, .aif, .aiff, or .caf file."
    }

    private var fileTooLargeMessage: String {
        "That file is too large. Please choose an audio file under 100 MB."
    }

    private struct PendingUpload {
        let lectureId: String
        var recording: PendingRecording?
        var sourceURL: URL?
        var preparedURL: URL?
    }

    private struct UploadAnalyticsContext {
        let uploadId: String
        let trigger: AudioUploadTrigger
        let fileSizeBytes: Int64?
        let fileDurationSeconds: Int?
        var uploadStart: Date?
    }

    private struct UploadCompletionContext {
        let uploadId: String
        let uploadStartTime: Date
        let totalBytes: Int64?
        let retriesCount: Int
    }
    
    private struct TranscriptionAnalyticsContext {
        let transcriptionId: String
        let uploadId: String?
        let audioSizeBytes: Int64?
        let audioDurationSeconds: Int?
        let trigger: TranscriptionTrigger
        let languageHint: String?
        var requestStart: Date?
        var requestSent: Bool
        var retriesCount: Int
    }

    private struct TranscriptionCorrelationContext {
        let transcriptionId: String
        let uploadId: String?
    }

    private struct SummarizationAnalyticsContext {
        let summarizationId: String
        let transcriptionId: String?
        let uploadId: String?
        let transcriptChars: Int?
        let transcriptBytes: Int64?
        let language: String?
        var requestStart: Date?
        var requestSent: Bool
        var retriesCount: Int
    }

    private struct PreparedAudioFile {
        let url: URL
        let durationMinutes: Int?
    }

    enum AudioUploadPreparationError: Error {
        case unsupportedFileType
        case fileTooLarge
        case unreadable
        case transcodeFailed
    }

    private func prepareAudioFileForUpload(
        from sourceURL: URL,
        lectureId: String
    ) async throws -> PreparedAudioFile {
        let allowedExtensions = supportedAudioExtensions
        let maxBytes = maxUploadFileSizeBytes
        
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessGranted { sourceURL.stopAccessingSecurityScopedResource() } }
            
            let sourceExtension = sourceURL.pathExtension.lowercased()
            if let error = LectureStore.audioUploadValidationError(
                fileExtension: sourceExtension,
                fileSizeBytes: nil,
                supportedExtensions: allowedExtensions,
                maxFileSizeBytes: maxBytes
            ) {
                throw error
            }
            
            let resourceValues = try sourceURL.resourceValues(forKeys: [
                .isReadableKey,
                .isRegularFileKey,
                .fileSizeKey
            ])
            guard resourceValues.isReadable == true, resourceValues.isRegularFile == true else {
                throw AudioUploadPreparationError.unreadable
            }
            let sourceFileSizeBytes = resourceValues.fileSize.map { Int64($0) }
            if let error = LectureStore.audioUploadValidationError(
                fileExtension: sourceExtension,
                fileSizeBytes: sourceFileSizeBytes,
                supportedExtensions: allowedExtensions,
                maxFileSizeBytes: maxBytes
            ) {
                throw error
            }
            
            let tempDirectory = fileManager.temporaryDirectory
            let tempSourceURL = tempDirectory
                .appendingPathComponent("upload-\(lectureId)-source")
                .appendingPathExtension(sourceExtension)
            if fileManager.fileExists(atPath: tempSourceURL.path) {
                try fileManager.removeItem(at: tempSourceURL)
            }
            
            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readingURL in
                do {
                    try fileManager.copyItem(at: readingURL, to: tempSourceURL)
                } catch {
                    copyError = error
                }
            }
            
            if let coordinationError {
                throw coordinationError
            }
            if let copyError {
                throw copyError
            }
            
            if let attributes = try? fileManager.attributesOfItem(atPath: tempSourceURL.path),
               let size = attributes[.size] as? NSNumber,
               size.int64Value > maxBytes {
                throw AudioUploadPreparationError.fileTooLarge
            }
            
            var finalURL = tempSourceURL
            if sourceExtension != "m4a" {
                let outputURL = tempDirectory
                    .appendingPathComponent("upload-\(lectureId)")
                    .appendingPathExtension("m4a")
                if fileManager.fileExists(atPath: outputURL.path) {
                    try fileManager.removeItem(at: outputURL)
                }
                
                let asset = AVURLAsset(url: tempSourceURL, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true
                ])
                guard let exportSession = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    throw AudioUploadPreparationError.transcodeFailed
                }
                
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                exportSession.shouldOptimizeForNetworkUse = true
                
                finalURL = try await withCheckedThrowingContinuation { continuation in
                    exportSession.exportAsynchronously {
                        switch exportSession.status {
                        case .completed:
                            continuation.resume(returning: outputURL)
                        case .failed, .cancelled:
                            continuation.resume(throwing: AudioUploadPreparationError.transcodeFailed)
                        default:
                            continuation.resume(throwing: AudioUploadPreparationError.transcodeFailed)
                        }
                    }
                }
            }
            
            if let attributes = try? fileManager.attributesOfItem(atPath: finalURL.path),
               let size = attributes[.size] as? NSNumber,
               size.int64Value > maxBytes {
                throw AudioUploadPreparationError.fileTooLarge
            }
            
            let durationAsset = AVURLAsset(url: finalURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            let durationMinutes = LectureStore.durationMinutes(
                fromSeconds: CMTimeGetSeconds(durationAsset.duration)
            )
            
            return PreparedAudioFile(url: finalURL, durationMinutes: durationMinutes)
        }.value
    }
    
    func createFolder(named name: String, folderId: String = UUID().uuidString) {
        guard let userId else {
            print("No userId set on LectureStore; cannot create folder.")
            return
        }
        
        let data: [String: Any] = [
            "name": name,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users")
            .document(userId)
            .collection("folders")
            .document(folderId)
            .setData(data) { error in
                if let error = error {
                    print("Error creating folder: \(error)")
                }
            }
    }
    
    func renameLecture(_ lecture: Lecture, to newTitle: String) {
        var updated = lecture
        updated.title = newTitle
        updateLecture(updated)
        
        guard let userId else { return }
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(["title": newTitle], merge: true) { error in
                if let error = error {
                    print("Error renaming lecture: \(error)")
                }
            }
    }
    
    func moveLecture(_ lecture: Lecture, to folder: Folder?) {
        var updated = lecture
        updated.folderId = folder?.id
        updated.folderName = folder?.name
        updateLecture(updated)
        
        guard let userId else { return }
        
        var data: [String: Any] = [:]
        if let folder {
            data["folderId"] = folder.id
            data["folderName"] = folder.name
        } else {
            data["folderId"] = FieldValue.delete()
            data["folderName"] = FieldValue.delete()
        }
        
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(data, merge: true) { error in
                if let error = error {
                    print("Error moving lecture: \(error)")
                }
            }
    }
    
    func deleteLecture(_ lecture: Lecture) {
        guard let userId else { return }

        if lecture.id == DemoLectureSeed.id {
            let data: [String: Any] = ["preferences.demoLectureHidden": true]
            db.collection("users")
                .document(userId)
                .setData(data, merge: true) { error in
                    if let error = error {
                        print("Error saving demo lecture preference: \(error)")
                    }
                }
        }
        
        // Optimistically remove locally
        lectures.removeAll { $0.id == lecture.id }
        clearPendingUpload(lectureId: lecture.id)
        
        let docRef = db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
        
        docRef.delete { [weak self] error in
            if let error = error {
                print("Error deleting lecture: \(error)")
            }
        }
        
        // Delete audio blob if present
        if let audioPath = lecture.audioPath, !audioPath.hasPrefix("demo/") {
            storage.reference(withPath: audioPath).delete { error in
                if let error = error {
                    print("Error deleting audio file: \(error)")
                }
            }
        }
    }
}

enum FeedbackError: LocalizedError {
    case missingUserId
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingUserId:
            return "You're not signed in. Please try again in a moment."
        case .missingEmail:
            return "Please enter an email address so we can follow up."
        }
    }
}

enum AccountDeletionError: LocalizedError {
    case missingUser
    case missingAuthToken
    case missingProjectId
    case invalidURL
    case invalidResponse
    case requestFailed(String)
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "You're not signed in. Please try again in a moment."
        case .missingAuthToken:
            return "We couldn't verify your session. Please try again."
        case .missingProjectId:
            return "Missing Firebase project configuration."
        case .invalidURL:
            return "Invalid delete endpoint URL."
        case .invalidResponse:
            return "Unexpected server response. Please try again."
        case .requestFailed(let message):
            return message
        case .signInFailed:
            return "We couldn't start a new session. Please restart the app."
        }
    }
}

extension LectureStore {
    static func mockStoreWithSampleData() -> LectureStore {
        LectureStore(seedMockData: true)
    }
}

private extension LectureStore {
    func restorePendingRecordings(for userId: String) {
        let stored = pendingRecordingStore.load(for: userId)
        guard !stored.isEmpty else {
            pendingUploads = [:]
            return
        }
        
        var valid: [PendingRecording] = []
        valid.reserveCapacity(stored.count)
        var restoredUploads: [String: PendingUpload] = [:]
        restoredUploads.reserveCapacity(stored.count)
        for recording in stored {
            if FileManager.default.fileExists(atPath: recording.filePath) {
                valid.append(recording)
                restoredUploads[recording.id] = PendingUpload(
                    lectureId: recording.id,
                    recording: recording,
                    sourceURL: nil,
                    preparedURL: recording.fileURL
                )
            } else {
                print("Pending recording missing on disk: \(recording.filePath)")
            }
        }
        
        pendingUploads = restoredUploads
        
        if valid.count != stored.count {
            pendingRecordingStore.replace(with: valid, for: userId)
        }
    }
    
    func resumePendingUploads() {
        guard !pendingUploads.isEmpty else { return }
        
        for pending in pendingUploads.values {
            guard let recording = pending.recording else { continue }
            guard !activeUploads.contains(recording.id) else { continue }
            Task { [weak self] in
                await self?.uploadLectureAudioWithRetry(
                    lectureId: recording.id,
                    title: recording.title,
                    recordingURL: recording.fileURL,
                    audioPath: recording.audioPath,
                    date: recording.date,
                    durationMinutes: recording.durationMinutes,
                    trigger: recording.trigger,
                    resume: true,
                    onError: nil
                )
            }
        }
    }
    
    func mergePendingLectures(into remoteLectures: [Lecture]) -> [Lecture] {
        let pending = pendingUploads.values.compactMap { $0.recording }
        guard !pending.isEmpty else { return remoteLectures }
        
        let remoteIds = Set(remoteLectures.map { $0.id })
        var merged = remoteLectures
        
        for recording in pending where !remoteIds.contains(recording.id) {
            merged.append(
                Lecture(
                    id: recording.id,
                    title: recording.title,
                    date: recording.date,
                    durationMinutes: recording.durationMinutes,
                    chargedMinutes: nil,
                    isFavorite: false,
                    status: .processing,
                    quotaReason: nil,
                    errorMessage: nil,
                    transcript: nil,
                    transcriptFormatted: nil,
                    summary: nil,
                    summaryInProgress: nil,
                    summaryTranslations: nil,
                    summaryTranslationRequests: [],
                    summaryTranslationInProgress: [],
                    summaryTranslationErrors: nil,
                    audioPath: recording.audioPath,
                    folderId: nil,
                    folderName: nil
                )
            )
        }
        
        return merged.sorted { $0.date > $1.date }
    }
    
    func clearPendingUpload(lectureId: String) {
        guard let pending = pendingUploads.removeValue(forKey: lectureId) else { return }
        if let recording = pending.recording {
            pendingRecordingStore.remove(id: lectureId, userId: recording.userId)
            RecordingStorage.removeFileIfExists(at: recording.fileURL)
        } else if let preparedURL = pending.preparedURL {
            RecordingStorage.removeFileIfExists(at: preparedURL)
        }
    }
    
    func seedDemoLectureIfNeeded(for userId: String) async {
        let userRef = db.collection("users").document(userId)
        do {
            let userSnapshot = try await userRef.getDocument()
            if let preferences = userSnapshot.data()?["preferences"] as? [String: Any],
               preferences["demoLectureHidden"] as? Bool == true {
                return
            }
            
            let lectureRef = userRef.collection("lectures").document(DemoLectureSeed.id)
            let lectureSnapshot = try await lectureRef.getDocument()
            if lectureSnapshot.exists {
                return
            }
            
            let now = Date()
            let demoDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            let summary: [String: Any] = [
                "mainTheme": DemoLectureSeed.summaryMainTheme,
                "keyPoints": DemoLectureSeed.summaryKeyPoints,
                "explicitAyatOrHadith": [],
                "weeklyActions": DemoLectureSeed.summaryWeeklyActions
            ]
            let data: [String: Any] = [
                "title": DemoLectureSeed.title,
                "date": Timestamp(date: demoDate),
                "isFavorite": false,
                "status": "ready",
                "transcript": DemoLectureSeed.transcript,
                "transcriptFormatted": DemoLectureSeed.transcript,
                "summary": summary,
                "audioPath": DemoLectureSeed.audioPath
            ]
            try await lectureRef.setData(data, merge: true)
        } catch {
            print("Failed to seed demo lecture: \(error.localizedDescription)")
        }
    }
}

struct LectureSummaryParser {
    static func parseSummary(from summaryMap: [String: Any]?) -> LectureSummary? {
        guard let summaryMap else { return nil }
        
        let mainTheme = summaryMap["mainTheme"] as? String ?? "Not mentioned"
        let keyPoints = summaryMap["keyPoints"] as? [String] ?? []
        let explicitAyatOrHadith = summaryMap["explicitAyatOrHadith"] as? [String] ?? []
        let weeklyActions = summaryMap["weeklyActions"] as? [String] ?? []
        
        return LectureSummary(
            mainTheme: mainTheme,
            keyPoints: keyPoints,
            explicitAyatOrHadith: explicitAyatOrHadith,
            weeklyActions: weeklyActions
        )
    }

    static func parseSummaryInProgress(from value: Any?) -> SummaryInProgressState? {
        if let isInProgress = value as? Bool {
            return isInProgress ?
                SummaryInProgressState(startedAt: nil, expiresAt: nil, isLegacy: true) :
                nil
        }
        
        if let map = value as? [String: Any] {
            let startedAt = (map["startedAt"] as? Timestamp)?.dateValue()
            let expiresAt = (map["expiresAt"] as? Timestamp)?.dateValue()
            if startedAt == nil && expiresAt == nil {
                return nil
            }
            return SummaryInProgressState(
                startedAt: startedAt,
                expiresAt: expiresAt,
                isLegacy: false
            )
        }
        
        return nil
    }
    
    static func parseSummaryTranslations(from map: [String: Any]?) -> [SummaryTranslation] {
        guard let map else { return [] }
        
        var translations: [SummaryTranslation] = []
        translations.reserveCapacity(map.count)
        
        for (languageCode, value) in map {
            guard let summaryMap = value as? [String: Any],
                  let summary = parseSummary(from: summaryMap) else { continue }
            translations.append(
                SummaryTranslation(languageCode: languageCode, summary: summary)
            )
        }
        
        return translations.sorted { $0.languageCode < $1.languageCode }
    }
    
    static func parseTranslationErrors(from map: [String: Any]?) -> [SummaryTranslationError] {
        guard let map else { return [] }
        
        var errors: [SummaryTranslationError] = []
        errors.reserveCapacity(map.count)
        
        for (languageCode, value) in map {
            guard let message = value as? String, !message.isEmpty else { continue }
            errors.append(
                SummaryTranslationError(languageCode: languageCode, message: message)
            )
        }
        
        return errors.sorted { $0.languageCode < $1.languageCode }
    }
    
    static func translationKeys(from data: Any?) -> [String] {
        if let map = data as? [String: Any] {
            return map.keys.sorted()
        }
        if let map = data as? [String: Bool] {
            return map.keys.sorted()
        }
        if let map = data as? [String: String] {
            return map.keys.sorted()
        }
        return []
    }
}

// MARK: - Duration helpers
extension LectureStore {
    private func durationMinutes(for recordingURL: URL) -> Int? {
        let asset = AVURLAsset(url: recordingURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        return Self.durationMinutes(fromSeconds: CMTimeGetSeconds(asset.duration))
    }

    private func fileDurationSeconds(for recordingURL: URL) -> Int? {
        let asset = AVURLAsset(url: recordingURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Int(seconds.rounded())
    }
    
    nonisolated static func durationMinutes(fromSeconds seconds: Double) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return max(1, minutes)
    }
    
    private func fillMissingDurationsIfNeeded(for lectures: [Lecture]) {
        for lecture in lectures {
            guard lecture.durationMinutes == nil,
                  let audioPath = lecture.audioPath,
                  !durationFetches.contains(lecture.id) else { continue }
            
            durationFetches.insert(lecture.id)
            
            storage.reference(withPath: audioPath).downloadURL { [weak self] url, error in
                guard let self else { return }
                guard let url else {
                    self.durationFetches.remove(lecture.id)
                    if let error { print("Failed to fetch audio URL for duration: \(error)") }
                    return
                }
                
                let asset = AVURLAsset(url: url, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true
                ])
                
                asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                    guard let self else { return }
                    var loadError: NSError?
                    let status = asset.statusOfValue(forKey: "duration", error: &loadError)
                    let capturedError = loadError
                    
                    Task { @MainActor in
                        self.durationFetches.remove(lecture.id)
                        
                        guard status == .loaded else {
                            if let capturedError {
                                print("Failed to load duration for \(lecture.id): \(capturedError)")
                            }
                            return
                        }
                        
                        let minutes = Self.durationMinutes(fromSeconds: CMTimeGetSeconds(asset.duration))
                        guard let minutes else { return }
                        self.persistDuration(minutes, for: lecture)
                    }
                }
            }
        }
    }
    
    func persistDuration(_ minutes: Int, for lecture: Lecture) {
        var updated = lecture
        updated.durationMinutes = minutes
        updateLecture(updated)
        
        guard let userId else { return }
        
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(["durationMinutes": minutes], merge: true)
    }
}

struct UserUsage {
    let plan: String
    let monthlyMinutesUsed: Int
    let monthlyKey: String?
    let freeLifetimeMinutesUsed: Int
    let freeLifetimeMinutesRemaining: Int?
    let periodStart: Date?
    let renewsAt: Date?
    
    var minutesRemaining: Int {
        if plan == "premium" {
            return max(0, 500 - monthlyMinutesUsed)
        } else {
            return max(0, 60 - freeLifetimeMinutesUsed)
        }
    }
}
