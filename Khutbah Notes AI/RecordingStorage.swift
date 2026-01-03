import Foundation

enum RecordingStorage {
    private static let recordingsDirectoryName = "Recordings"
    private static let pendingRecordingsFileName = "pending_recordings.json"
    
    static func recordingsDirectory() throws -> URL {
        let baseURL = try supportDirectory()
        let recordingsURL = baseURL.appendingPathComponent(
            recordingsDirectoryName,
            isDirectory: true
        )
        try ensureDirectoryExists(at: recordingsURL)
        return recordingsURL
    }
    
    static func newRecordingURL() throws -> URL {
        let recordingsURL = try recordingsDirectory()
        return recordingsURL
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
    
    static func pendingRecordingsURL() throws -> URL {
        try supportDirectory().appendingPathComponent(pendingRecordingsFileName)
    }
    
    static func removeFileIfExists(at url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("Failed to remove recording file: \(error)")
        }
    }
    
    private static func supportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try ensureDirectoryExists(at: baseURL)
        return baseURL
    }
    
    private static func ensureDirectoryExists(at url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
