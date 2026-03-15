import Foundation
import FirebaseAuth
import FirebaseCore

enum AudioRecapAPIError: LocalizedError {
    case missingUser
    case missingProjectId
    case invalidURL
    case invalidResponse
    case premiumRequired(String)
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
        case .premiumRequired(let message):
            return message
        case .server(let message):
            return message
        case .decoding:
            return "Could not parse recap response."
        }
    }
}

enum AudioRecapAPI {
    private static func baseURL() throws -> URL {
        guard let projectId = FirebaseApp.app()?.options.projectID else {
            throw AudioRecapAPIError.missingProjectId
        }
        guard let baseURL = URL(string: "https://us-central1-\(projectId).cloudfunctions.net") else {
            throw AudioRecapAPIError.invalidURL
        }
        return baseURL
    }

    private static func authToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AudioRecapAPIError.missingUser
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AudioRecapAPIError.invalidResponse)
                }
            }
        }
    }

    private static func request(
        path: String,
        method: String = "POST",
        body: [String: Any]
    ) async throws -> [String: Any] {
        let token = try await authToken()
        let base = try baseURL()
        guard let url = URL(string: path, relativeTo: base) else {
            throw AudioRecapAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AudioRecapAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = (json["error"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if http.statusCode == 403,
                   (json["code"] as? String) == "premium_required" {
                    let premiumMessage = {
                        if let message, !message.isEmpty {
                            return message
                        }
                        return "Audio recap is available on Premium."
                    }()
                    throw AudioRecapAPIError.premiumRequired(
                        premiumMessage
                    )
                }
                if let message, !message.isEmpty {
                    throw AudioRecapAPIError.server(message)
                }
            }
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw AudioRecapAPIError.server(message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AudioRecapAPIError.decoding
        }
        return json
    }

    static func requestLectureRecap(
        lectureId: String,
        options: AudioRecapOptions
    ) async throws -> AudioRecapState {
        var body = options.requestBody
        body["lectureId"] = lectureId
        let json = try await request(path: "requestLectureAudioRecap", body: body)
        return AudioRecapStateParser.parse(from: json)
    }

    static func getLectureRecap(
        lectureId: String,
        options: AudioRecapOptions
    ) async throws -> AudioRecapState {
        var body = options.requestBody
        body["lectureId"] = lectureId
        let json = try await request(path: "getLectureAudioRecap", body: body)
        return AudioRecapStateParser.parse(from: json)
    }

    static func requestMasjidRecap(
        masjidId: String,
        khutbahId: String,
        options: AudioRecapOptions
    ) async throws -> AudioRecapState {
        var body = options.requestBody
        body["masjidId"] = masjidId
        body["khutbahId"] = khutbahId
        let json = try await request(path: "requestMasjidAudioRecap", body: body)
        return AudioRecapStateParser.parse(from: json)
    }

    static func getMasjidRecap(
        masjidId: String,
        khutbahId: String,
        options: AudioRecapOptions
    ) async throws -> AudioRecapState {
        var body = options.requestBody
        body["masjidId"] = masjidId
        body["khutbahId"] = khutbahId
        let json = try await request(path: "getMasjidAudioRecap", body: body)
        return AudioRecapStateParser.parse(from: json)
    }
}
