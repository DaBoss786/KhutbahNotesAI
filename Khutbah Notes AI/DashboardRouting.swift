import Foundation

enum DashboardDeepLinkUserDefaultsKeys {
    static let appGroup = RecordingUserDefaultsKeys.appGroup
    static let pendingDashboardToken = "pendingDashboardToken"
}

enum DashboardDeepLinkDefaults {
    static let shared: UserDefaults =
        UserDefaults(suiteName: DashboardDeepLinkUserDefaultsKeys.appGroup) ?? .standard
}

struct DashboardDeepLinkStore {
    static func setPendingDashboard() {
        DashboardDeepLinkDefaults.shared.set(
            UUID().uuidString,
            forKey: DashboardDeepLinkUserDefaultsKeys.pendingDashboardToken
        )
    }
}

struct DashboardDeepLink {
    static let scheme = RecordingDeepLink.scheme
    static let host = "dashboard"

    static func url() -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }

    static func matches(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host
    }
}
