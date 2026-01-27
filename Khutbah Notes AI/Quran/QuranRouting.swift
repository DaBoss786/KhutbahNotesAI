import Foundation

enum QuranDeepLinkUserDefaultsKeys {
    static let appGroup = RecordingUserDefaultsKeys.appGroup
    static let pendingQuranTarget = "pendingQuranTarget"
}

enum QuranDeepLinkDefaults {
    static let shared: UserDefaults =
        UserDefaults(suiteName: QuranDeepLinkUserDefaultsKeys.appGroup) ?? .standard
}

struct QuranDeepLinkStore {
    static func setPendingTarget(_ target: QuranCitationTarget) {
        let value = "\(target.surahId):\(target.ayah)"
        QuranDeepLinkDefaults.shared.set(value, forKey: QuranDeepLinkUserDefaultsKeys.pendingQuranTarget)
    }

    static func clearPendingTarget() {
        QuranDeepLinkDefaults.shared.removeObject(forKey: QuranDeepLinkUserDefaultsKeys.pendingQuranTarget)
    }
}

struct QuranDeepLink {
    static let scheme = RecordingDeepLink.scheme
    static let host = "quran"
    static let surahQuery = "surah"
    static let ayahQuery = "ayah"
    static let idQuery = "id"

    static func url(for target: QuranCitationTarget) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: surahQuery, value: String(target.surahId)),
            URLQueryItem(name: ayahQuery, value: String(target.ayah)),
        ]
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }

    static func target(from url: URL) -> QuranCitationTarget? {
        guard url.scheme == scheme, url.host == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let idValue = components.queryItems?.first(where: { $0.name == idQuery })?.value,
           let targetFromId = parseVerseId(idValue) {
            return targetFromId
        }

        guard
            let surahValue = components.queryItems?.first(where: { $0.name == surahQuery })?.value,
            let ayahValue = components.queryItems?.first(where: { $0.name == ayahQuery })?.value,
            let surahId = Int(surahValue),
            let ayah = Int(ayahValue)
        else {
            return nil
        }

        return QuranCitationTarget(surahId: surahId, ayah: ayah)
    }

    static func parseVerseId(_ verseId: String) -> QuranCitationTarget? {
        let trimmed = verseId.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let surahId = Int(parts[0]),
              let ayah = Int(parts[1]) else {
            return nil
        }
        return QuranCitationTarget(surahId: surahId, ayah: ayah)
    }
}

