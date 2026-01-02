import Foundation

enum RecordingControlAction: String {
    case pause
    case resume
    case stop
}

enum RecordingRouteAction: String {
    case openRecording
    case showSaveCard
}

enum RecordingUserDefaultsKeys {
    static let appGroup = "group.com.medswipeapp.Khutbah-Notes-AI.onesignal"
    static let controlAction = "recordingControlAction"
    static let routeAction = "recordingRouteAction"
}

struct RecordingActionStore {
    static func setControlAction(_ action: RecordingControlAction) {
        RecordingDefaults.shared.set(action.rawValue, forKey: RecordingUserDefaultsKeys.controlAction)
    }

    static func setRouteAction(_ action: RecordingRouteAction) {
        RecordingDefaults.shared.set(action.rawValue, forKey: RecordingUserDefaultsKeys.routeAction)
    }
}

enum RecordingDefaults {
    static let shared: UserDefaults = UserDefaults(suiteName: RecordingUserDefaultsKeys.appGroup) ?? .standard
}

struct RecordingDeepLink {
    static let scheme = "khutbahnotesai"
    static let host = "recording"
    static let actionQuery = "action"

    static func url(for action: RecordingRouteAction) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: actionQuery, value: action.rawValue)]
        guard let url = components.url else {
            return URL(string: "\(scheme)://\(host)")!
        }
        return url
    }

    static func action(from url: URL) -> RecordingRouteAction? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let value = components?.queryItems?.first(where: { $0.name == actionQuery })?.value,
           let action = RecordingRouteAction(rawValue: value) {
            return action
        }
        return .openRecording
    }
}

enum LectureDeepLinkUserDefaultsKeys {
    static let appGroup = RecordingUserDefaultsKeys.appGroup
    static let pendingLectureId = "pendingLectureId"
}

enum LectureDeepLinkDefaults {
    static let shared: UserDefaults =
        UserDefaults(suiteName: LectureDeepLinkUserDefaultsKeys.appGroup) ?? .standard
}

struct LectureDeepLinkStore {
    static func setPendingLectureId(_ lectureId: String) {
        let trimmed = lectureId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        LectureDeepLinkDefaults.shared.set(
            trimmed,
            forKey: LectureDeepLinkUserDefaultsKeys.pendingLectureId
        )
    }

    static func clearPendingLectureId() {
        LectureDeepLinkDefaults.shared.removeObject(
            forKey: LectureDeepLinkUserDefaultsKeys.pendingLectureId
        )
    }
}

struct LectureDeepLink {
    static let scheme = RecordingDeepLink.scheme
    static let host = "lecture"
    static let lectureIdQuery = "lectureId"

    static func url(for lectureId: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let trimmed = lectureId.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: lectureIdQuery, value: trimmed),
        ]
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }

    static func lectureId(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let value = components?.queryItems?
            .first(where: { $0.name == lectureIdQuery })?.value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
