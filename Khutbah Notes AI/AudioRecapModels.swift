import Foundation

enum AudioRecapVoice: String, CaseIterable, Codable, Hashable {
    case male
    case female

    var label: String {
        switch self {
        case .male:
            return "Male"
        case .female:
            return "Female"
        }
    }
}

enum AudioRecapStyle: String, CaseIterable, Codable, Hashable {
    case concise
    case reflective
    case actionFocused = "action_focused"

    var label: String {
        switch self {
        case .concise:
            return "Concise"
        case .reflective:
            return "Reflective"
        case .actionFocused:
            return "Action-focused"
        }
    }
}

struct AudioRecapOptions: Hashable, Codable {
    static let fixedLengthSec = 180

    var voice: AudioRecapVoice = .male
    var style: AudioRecapStyle = .concise
    var language: String = "en"
    var targetLengthSec: Int = AudioRecapOptions.fixedLengthSec
    var promptVersion: String = "v1"

    var clampedLengthSec: Int {
        AudioRecapOptions.fixedLengthSec
    }

    var requestBody: [String: Any] {
        [
            "voice": voice.rawValue,
            "style": style.rawValue,
            "language": language,
            "targetLengthSec": clampedLengthSec,
            "promptVersion": promptVersion,
        ]
    }
}

enum AudioRecapStatus: String, Codable, Hashable {
    case missing
    case generating
    case processing
    case ready
    case failed
    case stale
    case unavailable

    var isInFlight: Bool {
        self == .generating || self == .processing
    }
}

struct AudioRecapState: Hashable {
    var status: AudioRecapStatus
    var variantKey: String
    var audioPath: String?
    var script: String?
    var durationSec: Int?
    var transcriptHash: String?
    var voice: AudioRecapVoice?
    var style: AudioRecapStyle?
    var language: String?
    var targetLengthSec: Int?
    var promptVersion: String?
    var textModel: String?
    var ttsModel: String?
    var errorMessage: String?
    var createdAt: Date?
    var updatedAt: Date?
    var generatedAt: Date?
    var stale: Bool

    static func unavailable(message: String, variantKey: String = "") -> AudioRecapState {
        AudioRecapState(
            status: .unavailable,
            variantKey: variantKey,
            audioPath: nil,
            script: nil,
            durationSec: nil,
            transcriptHash: nil,
            voice: nil,
            style: nil,
            language: nil,
            targetLengthSec: nil,
            promptVersion: nil,
            textModel: nil,
            ttsModel: nil,
            errorMessage: message,
            createdAt: nil,
            updatedAt: nil,
            generatedAt: nil,
            stale: false
        )
    }

    var userMessage: String? {
        switch status {
        case .missing:
            return nil
        case .generating, .processing:
            return "Generating your audio recap..."
        case .ready:
            return nil
        case .failed:
            return errorMessage?.isEmpty == false ?
                errorMessage :
                "Could not generate recap. Please try again."
        case .stale:
            return "Transcript changed. Regenerate to refresh recap."
        case .unavailable:
            return errorMessage?.isEmpty == false ?
                errorMessage :
                "Transcript unavailable for recap generation."
        }
    }
}

private enum AudioRecapDateParser {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }()

    static let fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        return iso8601.date(from: raw) ?? fallback.date(from: raw)
    }
}

enum AudioRecapStateParser {
    static func parse(
        from json: [String: Any],
        fallbackVariantKey: String = ""
    ) -> AudioRecapState {
        let statusRaw = (json["status"] as? String ?? "missing").lowercased()
        let status = AudioRecapStatus(rawValue: statusRaw) ?? .missing
        let voice = (json["voice"] as? String).flatMap(AudioRecapVoice.init(rawValue:))
        let style = (json["style"] as? String).flatMap(AudioRecapStyle.init(rawValue:))

        return AudioRecapState(
            status: status,
            variantKey: json["variantKey"] as? String ?? fallbackVariantKey,
            audioPath: json["audioPath"] as? String,
            script: json["script"] as? String,
            durationSec: json["durationSec"] as? Int,
            transcriptHash: json["transcriptHash"] as? String,
            voice: voice,
            style: style,
            language: json["language"] as? String,
            targetLengthSec: json["targetLengthSec"] as? Int,
            promptVersion: json["promptVersion"] as? String,
            textModel: json["textModel"] as? String,
            ttsModel: json["ttsModel"] as? String,
            errorMessage: json["error"] as? String,
            createdAt: AudioRecapDateParser.parse(json["createdAt"]),
            updatedAt: AudioRecapDateParser.parse(json["updatedAt"]),
            generatedAt: AudioRecapDateParser.parse(json["generatedAt"]),
            stale: json["stale"] as? Bool ?? false
        )
    }
}
