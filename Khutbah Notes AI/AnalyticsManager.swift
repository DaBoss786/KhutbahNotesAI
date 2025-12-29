import Foundation
import FirebaseAnalytics

enum AnalyticsEvent: String {
    case audioUpload = "audio_upload"
    case transcription = "transcription"
    case summarization = "summarization"
    case conversion = "conversion"
}

enum AnalyticsResult: String {
    case success
    case failure
}

enum AnalyticsParameterKey {
    static let result = "result"
}

struct AnalyticsManager {
    static func configure(isEnabled: Bool = true) {
        // Central toggle so consent wiring stays in one place.
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }
    
    static func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }
    
    static func log(_ event: AnalyticsEvent, result: AnalyticsResult? = nil, metadata: [String: Any]? = nil) {
        var parameters = sanitizedParameters(metadata)
        if let result {
            if parameters == nil {
                parameters = [:]
            }
            parameters?[AnalyticsParameterKey.result] = result.rawValue
        }
        Analytics.logEvent(event.rawValue, parameters: parameters)
    }
    
    private static func sanitizedParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        var sanitized: [String: Any] = [:]
        for (key, value) in parameters {
            switch value {
            case let value as String:
                sanitized[key] = value
            case let value as Int:
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
