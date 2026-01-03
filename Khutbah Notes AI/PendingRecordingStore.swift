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

protocol PendingRecordingStorage {
    func loadAll() -> [PendingRecording]
    func saveAll(_ recordings: [PendingRecording])
}

final class FilePendingRecordingStorage: PendingRecordingStorage {
    private let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    func loadAll() -> [PendingRecording] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let decoded = try? decoder.decode([PendingRecording].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveAll(_ recordings: [PendingRecording]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(recordings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save pending recordings: \(error)")
        }
    }
}

final class MemoryPendingRecordingStorage: PendingRecordingStorage {
    private var recordings: [PendingRecording] = []
    
    func loadAll() -> [PendingRecording] {
        recordings
    }
    
    func saveAll(_ recordings: [PendingRecording]) {
        self.recordings = recordings
    }
}

final class PendingRecordingStore {
    private let storage: PendingRecordingStorage
    private let accessLock = NSLock()
    
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.storage = FilePendingRecordingStorage(fileURL: fileURL)
        } else if let defaultURL = try? RecordingStorage.pendingRecordingsURL() {
            self.storage = FilePendingRecordingStorage(fileURL: defaultURL)
        } else {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pending_recordings.json")
            self.storage = FilePendingRecordingStorage(fileURL: fallbackURL)
        }
    }
    
    init(storage: PendingRecordingStorage) {
        self.storage = storage
    }
    
    func load(for userId: String) -> [PendingRecording] {
        withLock {
            storage.loadAll().filter { $0.userId == userId }
        }
    }
    
    func replace(with recordings: [PendingRecording], for userId: String? = nil) {
        withLock {
            var updated = storage.loadAll()
            if let userId {
                updated.removeAll { $0.userId == userId }
                updated.append(contentsOf: recordings)
            } else {
                updated = recordings
            }
            storage.saveAll(updated)
        }
    }
    
    func upsert(_ recording: PendingRecording) {
        withLock {
            var recordings = storage.loadAll()
            if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                recordings[index] = recording
            } else {
                recordings.append(recording)
            }
            storage.saveAll(recordings)
        }
    }
    
    func remove(id: String, userId: String) {
        withLock {
            var recordings = storage.loadAll()
            recordings.removeAll { $0.id == id && $0.userId == userId }
            storage.saveAll(recordings)
        }
    }
    
    private func withLock<T>(_ work: () -> T) -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        return work()
    }
    
}
