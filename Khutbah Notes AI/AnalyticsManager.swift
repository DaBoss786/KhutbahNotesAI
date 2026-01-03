import Foundation
import FirebaseAnalytics

enum AnalyticsEvent: String {
    case audioUploadAttempt = "audio_upload_attempt"
    case audioUploadStarted = "audio_upload_started"
    case audioUploadFailed = "audio_upload_failed"
    case audioUploadSuccess = "audio_upload_success"
    case transcriptionRequestAttempt = "transcription_request_attempt"
    case transcriptionRequestSent = "transcription_request_sent"
    case transcriptionFailed = "transcription_failed"
    case transcriptionSuccess = "transcription_success"
    case summarizationRequestAttempt = "summarization_request_attempt"
    case summarizationRequestSent = "summarization_request_sent"
    case summarizationFailed = "summarization_failed"
    case summarizationSuccess = "summarization_success"
    case onboardingStepViewed = "onboarding_step_viewed"
    case onboardingCompleted = "onboarding_completed"
    case onboardingNotificationsChoice = "onboarding_notifications_choice"
    case onboardingPaywallResult = "onboarding_paywall_result"
}

enum AudioUploadTrigger: String, Codable {
    case recording
    case retake
    case manual
}

enum AudioUploadFailureStage: String {
    case prepare
    case auth
    case upload
    case finalize
}

enum AudioUploadErrorCode: String {
    // Keep this vocabulary tight for stable dashboards.
    case auth
    case network
    case timeout
    case server5xx = "server_5xx"
    case client4xx = "client_4xx"
    case fileTooLarge = "file_too_large"
    case canceled
    case unknown
}

enum TranscriptionTrigger: String {
    case auto
    case manual
}

enum TranscriptionFailureStage: String {
    case prepare
    case auth
    case request
    case processing
}

enum TranscriptionErrorCode: String {
    // Keep this vocabulary tight for stable dashboards.
    case auth
    case network
    case timeout
    case server5xx = "server_5xx"
    case client4xx = "client_4xx"
    case invalidMedia = "invalid_media"
    case quota
    case canceled
    case unknown
}

enum SummarizationTrigger: String {
    case auto
    case manual
}

enum SummarizationFailureStage: String {
    case prepare
    case auth
    case request
    case processing
}

enum SummarizationErrorCode: String {
    // Keep this vocabulary tight for stable dashboards.
    case auth
    case network
    case timeout
    case server5xx = "server_5xx"
    case client4xx = "client_4xx"
    case invalidInput = "invalid_input"
    case quota
    case canceled
    case unknown
}

enum OnboardingStep: String {
    case welcome
    case remember
    case integrity
    case howItWorks = "how_it_works"
    case jumuahReminder = "jumuah_reminder"
    case notificationsPrePrompt = "notifications_pre_prompt"
    case paywall
}

enum OnboardingNotificationsChoice: String {
    case push
    case provisional
    case no
}

enum OnboardingPaywallResult: String {
    case purchased
    case dismissed
    case restored
}

enum AnalyticsParameterKey {
    static let uploadId = "upload_id"
    static let transcriptionId = "transcription_id"
    static let summarizationId = "summarization_id"
    static let fileSize = "file_size"
    static let fileDuration = "file_duration"
    static let audioSize = "audio_size"
    static let audioDuration = "audio_duration"
    static let networkType = "network_type"
    static let trigger = "trigger"
    static let languageHint = "language_hint"
    static let language = "language"
    static let backend = "backend"
    static let requestBytes = "request_bytes"
    static let resume = "resume"
    static let failureStage = "failure_stage"
    static let errorCode = "error_code"
    static let httpStatus = "http_status"
    static let retryable = "retryable"
    static let totalBytes = "total_bytes"
    static let durationMs = "duration_ms"
    static let processingMs = "processing_ms"
    static let retriesCount = "retries_count"
    static let transcriptChars = "transcript_chars"
    static let summaryChars = "summary_chars"
    static let reason = "reason"
    static let step = "step"
    static let totalSteps = "total_steps"
    static let choice = "choice"
    static let source = "source"
    static let result = "result"
    static let jumuahTime = "jumuah_time"
    static let timezone = "timezone"
    static let planId = "plan_id"
    static let productId = "product_id"
    static let price = "price"
    static let currency = "currency"
}

struct AnalyticsManager {
    
    static func configure(isEnabled: Bool = true) {
        // Central toggle so consent wiring stays in one place.
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }
    
    static func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }
    
    static func logAudioUploadAttempt(
        uploadId: String,
        fileSizeBytes: Int64?,
        fileDurationSeconds: Int?,
        networkType: String,
        trigger: AudioUploadTrigger
    ) {
        log(.audioUploadAttempt, parameters: [
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.fileSize: fileSizeBytes,
            AnalyticsParameterKey.fileDuration: fileDurationSeconds,
            AnalyticsParameterKey.networkType: networkType,
            AnalyticsParameterKey.trigger: trigger.rawValue
        ])
    }
    
    static func logAudioUploadStarted(uploadId: String, resume: Bool) {
        log(.audioUploadStarted, parameters: [
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.resume: resume
        ])
    }
    
    static func logAudioUploadFailed(
        uploadId: String,
        failureStage: AudioUploadFailureStage,
        errorCode: AudioUploadErrorCode,
        networkType: String,
        retryable: Bool
    ) {
        log(.audioUploadFailed, parameters: [
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.failureStage: failureStage.rawValue,
            AnalyticsParameterKey.errorCode: errorCode.rawValue,
            AnalyticsParameterKey.networkType: networkType,
            AnalyticsParameterKey.retryable: retryable
        ])
    }
    
    static func logAudioUploadSuccess(
        uploadId: String,
        totalBytes: Int64?,
        durationMs: Int?,
        retriesCount: Int
    ) {
        log(.audioUploadSuccess, parameters: [
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.totalBytes: totalBytes,
            AnalyticsParameterKey.durationMs: durationMs,
            AnalyticsParameterKey.retriesCount: retriesCount
        ])
    }
    
    static func logTranscriptionRequestAttempt(
        transcriptionId: String,
        uploadId: String?,
        audioDurationSeconds: Int?,
        audioSizeBytes: Int64?,
        networkType: String,
        trigger: TranscriptionTrigger,
        languageHint: String?
    ) {
        log(.transcriptionRequestAttempt, parameters: [
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.audioDuration: audioDurationSeconds,
            AnalyticsParameterKey.audioSize: audioSizeBytes,
            AnalyticsParameterKey.networkType: networkType,
            AnalyticsParameterKey.trigger: trigger.rawValue,
            AnalyticsParameterKey.languageHint: languageHint
        ])
    }
    
    static func logTranscriptionRequestSent(
        transcriptionId: String,
        uploadId: String?,
        backend: String,
        requestBytes: Int64?
    ) {
        log(.transcriptionRequestSent, parameters: [
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.backend: backend,
            AnalyticsParameterKey.requestBytes: requestBytes
        ])
    }
    
    static func logTranscriptionFailed(
        transcriptionId: String,
        uploadId: String?,
        failureStage: TranscriptionFailureStage,
        errorCode: TranscriptionErrorCode,
        httpStatus: Int?,
        retryable: Bool,
        networkType: String
    ) {
        log(.transcriptionFailed, parameters: [
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.failureStage: failureStage.rawValue,
            AnalyticsParameterKey.errorCode: errorCode.rawValue,
            AnalyticsParameterKey.httpStatus: httpStatus,
            AnalyticsParameterKey.retryable: retryable,
            AnalyticsParameterKey.networkType: networkType
        ])
    }
    
    static func logTranscriptionSuccess(
        transcriptionId: String,
        uploadId: String?,
        transcriptChars: Int?,
        processingMs: Int?,
        retriesCount: Int
    ) {
        log(.transcriptionSuccess, parameters: [
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.transcriptChars: transcriptChars,
            AnalyticsParameterKey.processingMs: processingMs,
            AnalyticsParameterKey.retriesCount: retriesCount
        ])
    }

    static func logSummarizationRequestAttempt(
        summarizationId: String,
        transcriptionId: String?,
        uploadId: String?,
        transcriptChars: Int?,
        language: String?,
        networkType: String,
        trigger: SummarizationTrigger
    ) {
        log(.summarizationRequestAttempt, parameters: [
            AnalyticsParameterKey.summarizationId: summarizationId,
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.transcriptChars: transcriptChars,
            AnalyticsParameterKey.language: language,
            AnalyticsParameterKey.networkType: networkType,
            AnalyticsParameterKey.trigger: trigger.rawValue
        ])
    }

    static func logSummarizationRequestSent(
        summarizationId: String,
        transcriptionId: String?,
        uploadId: String?,
        backend: String,
        requestBytes: Int64?
    ) {
        log(.summarizationRequestSent, parameters: [
            AnalyticsParameterKey.summarizationId: summarizationId,
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.backend: backend,
            AnalyticsParameterKey.requestBytes: requestBytes
        ])
    }

    static func logSummarizationFailed(
        summarizationId: String,
        transcriptionId: String?,
        uploadId: String?,
        failureStage: SummarizationFailureStage,
        errorCode: SummarizationErrorCode,
        httpStatus: Int?,
        retryable: Bool,
        networkType: String
    ) {
        log(.summarizationFailed, parameters: [
            AnalyticsParameterKey.summarizationId: summarizationId,
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.failureStage: failureStage.rawValue,
            AnalyticsParameterKey.errorCode: errorCode.rawValue,
            AnalyticsParameterKey.httpStatus: httpStatus,
            AnalyticsParameterKey.retryable: retryable,
            AnalyticsParameterKey.networkType: networkType
        ])
    }

    static func logSummarizationSuccess(
        summarizationId: String,
        transcriptionId: String?,
        uploadId: String?,
        summaryChars: Int?,
        processingMs: Int?,
        retriesCount: Int
    ) {
        log(.summarizationSuccess, parameters: [
            AnalyticsParameterKey.summarizationId: summarizationId,
            AnalyticsParameterKey.transcriptionId: transcriptionId,
            AnalyticsParameterKey.uploadId: uploadId,
            AnalyticsParameterKey.summaryChars: summaryChars,
            AnalyticsParameterKey.processingMs: processingMs,
            AnalyticsParameterKey.retriesCount: retriesCount
        ])
    }

    static func logOnboardingStepViewed(
        step: OnboardingStep,
        totalSteps: Int?,
        jumuahTime: String? = nil,
        timezone: String? = nil,
        source: String? = nil
    ) {
        log(.onboardingStepViewed, parameters: [
            AnalyticsParameterKey.step: step.rawValue,
            AnalyticsParameterKey.totalSteps: totalSteps,
            AnalyticsParameterKey.jumuahTime: jumuahTime,
            AnalyticsParameterKey.timezone: timezone,
            AnalyticsParameterKey.source: source
        ])
    }

    static func logOnboardingCompleted(step: OnboardingStep, totalSteps: Int?) {
        log(.onboardingCompleted, parameters: [
            AnalyticsParameterKey.step: step.rawValue,
            AnalyticsParameterKey.totalSteps: totalSteps
        ])
    }

    static func logOnboardingNotificationsChoice(
        choice: OnboardingNotificationsChoice,
        step: OnboardingStep,
        totalSteps: Int?
    ) {
        log(.onboardingNotificationsChoice, parameters: [
            AnalyticsParameterKey.choice: choice.rawValue,
            AnalyticsParameterKey.step: step.rawValue,
            AnalyticsParameterKey.totalSteps: totalSteps
        ])
    }

    static func logOnboardingPaywallResult(
        result: OnboardingPaywallResult,
        step: OnboardingStep,
        planId: String? = nil,
        productId: String? = nil,
        price: Double? = nil,
        currency: String? = nil
    ) {
        log(.onboardingPaywallResult, parameters: [
            AnalyticsParameterKey.result: result.rawValue,
            AnalyticsParameterKey.step: step.rawValue,
            AnalyticsParameterKey.planId: planId,
            AnalyticsParameterKey.productId: productId,
            AnalyticsParameterKey.price: price,
            AnalyticsParameterKey.currency: currency
        ])
    }
    
    private static func log(_ event: AnalyticsEvent, parameters: [String: Any?]) {
        let sanitized = sanitizedParameters(parameters)
        Analytics.logEvent(event.rawValue, parameters: sanitized)
    }
    
    private static func sanitizedParameters(_ parameters: [String: Any?]) -> [String: Any]? {
        var sanitized: [String: Any] = [:]
        for (key, value) in parameters {
            guard let value else { continue }
            switch value {
            case let value as String:
                sanitized[key] = value
            case let value as Int:
                sanitized[key] = value
            case let value as Int64:
                sanitized[key] = value
            case let value as Double:
                sanitized[key] = value
            case let value as Float:
                sanitized[key] = Double(value)
            case let value as Bool:
                sanitized[key] = value
            default:
                continue
            }
        }
        return sanitized.isEmpty ? nil : sanitized
    }
}
