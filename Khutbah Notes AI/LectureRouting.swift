import Foundation

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
