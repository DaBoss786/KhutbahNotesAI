import Foundation
import FirebaseAuth
import FirebaseCore

enum MasjidAdminAPIError: LocalizedError {
    case missingUser
    case missingProjectId
    case invalidURL
    case invalidResponse
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "You're not signed in."
        case .missingProjectId:
            return "Missing Firebase project configuration."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Unexpected server response."
        case .server(let message):
            return message
        case .decoding:
            return "Could not parse server response."
        }
    }
}

enum MasjidAdminAPI {
    private static func baseURL() throws -> URL {
        guard let projectId = FirebaseApp.app()?.options.projectID else {
            throw MasjidAdminAPIError.missingProjectId
        }
        guard let baseURL = URL(string: "https://us-central1-\(projectId).cloudfunctions.net") else {
            throw MasjidAdminAPIError.invalidURL
        }
        return baseURL
    }

    private static func authToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw MasjidAdminAPIError.missingUser
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: MasjidAdminAPIError.invalidResponse)
                }
            }
        }
    }

    private static func request(
        path: String,
        method: String = "POST",
        body: [String: Any]? = nil
    ) async throws -> Data {
        let token = try await authToken()
        let base = try baseURL()
        guard let url = URL(string: path, relativeTo: base) else {
            throw MasjidAdminAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MasjidAdminAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw MasjidAdminAPIError.server(message)
        }
        return data
    }

    static func fetchAdminCapability() async throws -> Bool {
        let data = try await request(path: "getMasjidAdminCapability", method: "GET")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isAdmin = json["isAdmin"] as? Bool else {
            throw MasjidAdminAPIError.decoding
        }
        return isAdmin
    }

    static func upsertMasjid(
        masjidId: String?,
        name: String,
        city: String,
        state: String?,
        country: String,
        imageUrl: String?
    ) async throws {
        var body: [String: Any] = [
            "name": name,
            "city": city,
            "country": country,
        ]
        if let state, !state.isEmpty {
            body["state"] = state
        }
        if let masjidId, !masjidId.isEmpty {
            body["masjidId"] = masjidId
        }
        if let imageUrl, !imageUrl.isEmpty {
            body["imageUrl"] = imageUrl
        }
        _ = try await request(path: "adminUpsertMasjid", body: body)
    }

    static func queueKhutbah(
        masjidId: String,
        youtubeUrl: String,
        title: String?,
        speaker: String?,
        manualTranscript: String?
    ) async throws {
        var body: [String: Any] = [
            "masjidId": masjidId,
            "youtubeUrl": youtubeUrl,
        ]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["title"] = title
        }
        if let speaker, !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["speaker"] = speaker
        }
        if let manualTranscript,
           !manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["manualTranscript"] = manualTranscript
        }
        _ = try await request(path: "adminQueueMasjidKhutbah", body: body)
    }
}
