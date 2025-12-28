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

    static func clearControlAction() {
        RecordingDefaults.shared.removeObject(forKey: RecordingUserDefaultsKeys.controlAction)
    }

    static func setRouteAction(_ action: RecordingRouteAction) {
        RecordingDefaults.shared.set(action.rawValue, forKey: RecordingUserDefaultsKeys.routeAction)
    }

    static func clearRouteAction() {
        RecordingDefaults.shared.removeObject(forKey: RecordingUserDefaultsKeys.routeAction)
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
