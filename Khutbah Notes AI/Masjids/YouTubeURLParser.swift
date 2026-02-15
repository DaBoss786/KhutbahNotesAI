import Foundation

enum YouTubeURLParser {
    private static let validIdPattern = "^[A-Za-z0-9_-]{11}$"
    private static let watchHosts = ["youtube.com", "www.youtube.com", "m.youtube.com"]
    private static let shortHosts = ["youtu.be", "www.youtu.be"]
    private static let embedHost = "www.youtube.com"

    private static var appIdentityURLString: String? {
        guard let bundleId = Bundle.main.bundleIdentifier?.lowercased(),
              !bundleId.isEmpty else {
            return nil
        }
        return "https://\(bundleId)"
    }

    static func videoId(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidVideoId(trimmed) {
            return trimmed
        }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased() else {
            return nil
        }

        if shortHosts.contains(host) {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return isValidVideoId(path) ? path : nil
        }

        if watchHosts.contains(host) {
            if let queryId = components.queryItems?
                .first(where: { $0.name == "v" })?.value,
               isValidVideoId(queryId) {
                return queryId
            }

            let pathParts = components.path
                .split(separator: "/")
                .map(String.init)
            if pathParts.count >= 2 {
                let candidate: String?
                switch pathParts[0] {
                case "embed", "shorts", "live":
                    candidate = pathParts[1]
                case "watch":
                    candidate = nil
                default:
                    candidate = nil
                }
                if let candidate, isValidVideoId(candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func embedRequest(for videoId: String, sourceURL: String? = nil) -> URLRequest? {
        guard let embedURL = embedURL(for: videoId, sourceURL: sourceURL) else { return nil }

        var request = URLRequest(url: embedURL)
        if let appIdentityURLString {
            request.setValue(appIdentityURLString, forHTTPHeaderField: "Referer")
        }
        return request
    }

    static func embedURL(for videoId: String, sourceURL: String? = nil) -> URL? {
        guard isValidVideoId(videoId) else { return nil }
        var components = URLComponents(string: "https://\(embedHost)/embed/\(videoId)")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
        ]

        if let appIdentityURLString {
            queryItems.append(URLQueryItem(name: "origin", value: appIdentityURLString))
            queryItems.append(URLQueryItem(name: "widget_referrer", value: appIdentityURLString))
        }

        if let sourceURL,
           let sourceComponents = URLComponents(string: sourceURL),
           let siValue = sourceComponents.queryItems?
            .first(where: { $0.name == "si" })?.value,
           !siValue.isEmpty {
            queryItems.append(URLQueryItem(name: "si", value: siValue))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    private static func isValidVideoId(_ value: String) -> Bool {
        value.range(of: validIdPattern, options: .regularExpression) != nil
    }
}
