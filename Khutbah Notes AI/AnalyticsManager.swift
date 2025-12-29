import Foundation
import FirebaseAnalytics

enum AnalyticsEvent: String {
    case audioUploadAttempt = "audio_upload_attempt"
    case audioUploadStarted = "audio_upload_started"
    case audioUploadFailed = "audio_upload_failed"
    case audioUploadSuccess = "audio_upload_success"
}

enum AudioUploadTrigger: String {
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

enum AnalyticsParameterKey {
    static let uploadId = "upload_id"
    static let fileSize = "file_size"
    static let fileDuration = "file_duration"
    static let networkType = "network_type"
    static let trigger = "trigger"
    static let resume = "resume"
    static let failureStage = "failure_stage"
    static let errorCode = "error_code"
    static let retryable = "retryable"
    static let totalBytes = "total_bytes"
    static let durationMs = "duration_ms"
    static let retriesCount = "retries_count"
    static let reason = "reason"
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
