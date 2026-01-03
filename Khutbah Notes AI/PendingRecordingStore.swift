import Foundation

struct PendingRecording: Codable, Identifiable {
    let id: String
    let userId: String
    let title: String
    let date: Date
    let durationMinutes: Int?
    let audioPath: String
    let filePath: String
    let trigger: AudioUploadTrigger
    
    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}

final class PendingRecordingStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "PendingRecordingStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let defaultURL = try? RecordingStorage.pendingRecordingsURL() {
            self.fileURL = defaultURL
        } else {
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pending_recordings.json")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func load(for userId: String) -> [PendingRecording] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            guard let decoded = try? decoder.decode([PendingRecording].self, from: data) else {
                return []
            }
            return decoded.filter { $0.userId == userId }
        }
    }
    
    func replace(with recordings: [PendingRecording]) {
        queue.sync {
            do {
                let data = try encoder.encode(recordings)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                print("Failed to save pending recordings: \(error)")
            }
        }
    }
    
    func upsert(_ recording: PendingRecording) {
        var recordings = load(for: recording.userId)
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        } else {
            recordings.append(recording)
        }
        replace(with: recordings)
    }
    
    func remove(id: String, userId: String) {
        var recordings = load(for: userId)
        recordings.removeAll { $0.id == id }
        replace(with: recordings)
    }
}
