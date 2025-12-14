import SwiftUI
import Combine
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class LectureStore: ObservableObject {
    @Published var lectures: [Lecture] = []
    @Published var folders: [Folder] = []
    @Published var userUsage: UserUsage?
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
    private var folderListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private(set) var userId: String?
    private var durationFetches: Set<String> = []
    
    init(seedMockData: Bool = false) {
        if seedMockData {
            addMockData()
        }
    }
    
    func addMockData() {
        let today = Date()
        let calendar = Calendar.current
        
        lectures = [
            Lecture(
                id: "mock-1",
                title: "Tafseer of Surah Al-Kahf",
                date: today,
                durationMinutes: 45,
                chargedMinutes: 45,
                isFavorite: true,
                status: .ready,
                quotaReason: nil,
                transcript: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            ),
            Lecture(
                id: "mock-2",
                title: "Understanding Taqwa",
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                durationMinutes: 32,
                chargedMinutes: 32,
                isFavorite: false,
                status: .processing,
                quotaReason: nil,
                transcript: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            ),
            Lecture(
                id: "mock-3",
                title: "Mercy and Patience",
                date: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                durationMinutes: nil,
                chargedMinutes: nil,
                isFavorite: false,
                status: .failed,
                quotaReason: nil,
                transcript: nil,
                summary: nil,
                audioPath: nil,
                folderId: nil,
                folderName: nil
            )
        ]
    }
    
    func updateLecture(_ lecture: Lecture) {
        guard let index = lectures.firstIndex(where: { $0.id == lecture.id }) else { return }
        lectures[index] = lecture
    }
    
    func saveJumuahStartTime(_ time: String, timezoneIdentifier: String) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot save Jumu'ah start time.")
            return
        }
        
        let data: [String: Any] = [
            "preferences": [
                "jumuahStartTime": time,
                "jumuahTimezone": timezoneIdentifier
            ]
        ]
        
        do {
            try await db.collection("users").document(userId).setData(data, merge: true)
            try await removeLegacyPreferenceDotFields(keys: ["jumuahStartTime", "jumuahTimezone"])
            print("Saved Jumu'ah start time for user \(userId): \(time) (\(timezoneIdentifier))")
        } catch {
            print("Failed to save Jumu'ah start time: \(error.localizedDescription)")
        }
    }
    
    func saveNotificationPreference(_ preference: String) async {
        guard let userId else {
            print("No userId set on LectureStore; cannot save notification preference.")
            return
        }
        
        let data: [String: Any] = [
            "preferences": [
                "notificationPreference": preference
            ]
        ]
        
        do {
            try await db.collection("users").document(userId).setData(data, merge: true)
            try await removeLegacyPreferenceDotFields(keys: ["notificationPreference"])
            print("Saved notification preference for user \(userId): \(preference)")
        } catch {
            print("Failed to save notification preference: \(error.localizedDescription)")
        }
    }
    
    private func removeLegacyPreferenceDotFields(keys: [String]) async throws {
        guard let userId else { return }
        var deletes: [String: Any] = [:]
        keys.forEach { key in
            deletes["preferences.\(key)"] = FieldValue.delete()
        }
        if !deletes.isEmpty {
            try await db.collection("users").document(userId).setData(deletes, merge: true)
        }
    }
    
    func start(for userId: String) {
        self.userId = userId
        
        // Stop any previous listener
        listener?.remove()
        folderListener?.remove()
        userListener?.remove()
        
        // Listen to this user's lectures collection
        listener = db.collection("users")
            .document(userId)
            .collection("lectures")
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to lectures: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.lectures = []
                    return
                }
                
                self.lectures = documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    
                    guard let title = data["title"] as? String,
                          let timestamp = data["date"] as? Timestamp,
                          let statusString = data["status"] as? String else {
                        return nil
                    }
                    
                    let date = timestamp.dateValue()
                    let durationMinutes = data["durationMinutes"] as? Int
                    let chargedMinutes = data["chargedMinutes"] as? Int
                    let isFavorite = data["isFavorite"] as? Bool ?? false
                    let transcript = data["transcript"] as? String
                    let audioPath = data["audioPath"] as? String
                    let folderId = data["folderId"] as? String
                    let folderName = data["folderName"] as? String
                    let quotaReason = data["quotaReason"] as? String
                    
                    var summary: LectureSummary? = nil
                    if let summaryMap = data["summary"] as? [String: Any] {
                        let mainTheme = summaryMap["mainTheme"] as? String ?? "Not mentioned"
                        let keyPoints = summaryMap["keyPoints"] as? [String] ?? []
                        let explicitAyatOrHadith = summaryMap["explicitAyatOrHadith"] as? [String] ?? []
                        let weeklyActions = summaryMap["weeklyActions"] as? [String] ?? []
                        
                        summary = LectureSummary(
                            mainTheme: mainTheme,
                            keyPoints: keyPoints,
                            explicitAyatOrHadith: explicitAyatOrHadith,
                            weeklyActions: weeklyActions
                        )
                    }
                    
                    let status: LectureStatus
                    switch statusString {
                    case "recording": status = .recording
                    case "processing": status = .processing
                    case "summarizing": status = .summarizing
                    case "transcribed": status = .transcribed
                    case "ready": status = .ready
                    case "blocked_quota": status = .blockedQuota
                    case "failed": status = .failed
                    default: status = .processing
                    }
                    
                    return Lecture(
                        id: id,
                        title: title,
                        date: date,
                        durationMinutes: durationMinutes,
                        chargedMinutes: chargedMinutes,
                        isFavorite: isFavorite,
                        status: status,
                        quotaReason: quotaReason,
                        transcript: transcript,
                        summary: summary,
                        audioPath: audioPath,
                        folderId: folderId,
                        folderName: folderName
                    )
                }
                
                self.fillMissingDurationsIfNeeded(for: self.lectures)
            }
        
        userListener = db.collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Error listening to user doc: \(error)")
                    return
                }
                guard let data = snapshot?.data() else { return }
                
                let plan = data["plan"] as? String ?? "free"
                let monthlyMinutesUsed = data["monthlyMinutesUsed"] as? Int ?? 0
                let monthlyKey = data["monthlyKey"] as? String
                let freeLifetimeMinutesUsed = data["freeLifetimeMinutesUsed"] as? Int ?? 0
                let periodStart = (data["periodStart"] as? Timestamp)?.dateValue()
                let renewsAt = (data["renewsAt"] as? Timestamp)?.dateValue()
                
                self.userUsage = UserUsage(
                    plan: plan,
                    monthlyMinutesUsed: monthlyMinutesUsed,
                    monthlyKey: monthlyKey,
                    freeLifetimeMinutesUsed: freeLifetimeMinutesUsed,
                    periodStart: periodStart,
                    renewsAt: renewsAt
                )
            }
        
        // Listen to this user's folders collection
        folderListener = db.collection("users")
            .document(userId)
            .collection("folders")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    print("Error listening to folders: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.folders = []
                    return
                }
                
                self.folders = documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    guard let name = data["name"] as? String else { return nil }
                    
                    let createdAt: Date
                    if let ts = data["createdAt"] as? Timestamp {
                        createdAt = ts.dateValue()
                    } else {
                        createdAt = Date()
                    }
                    
                    return Folder(id: id, name: name, createdAt: createdAt)
                }
            }
    }
    
    func createLecture(withTitle title: String, recordingURL: URL) {
        guard let userId = userId else {
            print("No userId set on LectureStore; cannot create lecture.")
            return
        }
        
        let lectureId = UUID().uuidString
        let now = Date()
        let audioPath = "audio/\(userId)/\(lectureId).m4a"
        let durationMinutes = durationMinutes(for: recordingURL)
        
        // Optimistically insert a local lecture while upload happens
        let newLecture = Lecture(
            id: lectureId,
            title: title,
            date: now,
            durationMinutes: durationMinutes,
            chargedMinutes: nil,
            isFavorite: false,
            status: .processing,
            quotaReason: nil,
            transcript: nil,
            summary: nil,
            audioPath: audioPath,
            folderId: nil,
            folderName: nil
        )
        
        // Insert at top so UI feels instant; Firestore listener will overwrite as needed
        lectures.insert(newLecture, at: 0)
        
        // Storage path: audio/{userId}/{lectureId}.m4a
        let audioRef = storage.reference(withPath: audioPath)
        
        audioRef.putFile(from: recordingURL, metadata: nil) { [weak self] metadata, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error uploading audio: \(error)")
                // Optionally update status to .failed in Firestore later
                return
            }
            
            let audioPath = audioRef.fullPath
            
            var docData: [String: Any] = [
                "title": title,
                "date": Timestamp(date: now),
                "isFavorite": false,
                "status": "processing",
                "transcript": NSNull(),
                "summary": NSNull(),
                "audioPath": audioPath
            ]
            docData["durationMinutes"] = durationMinutes ?? NSNull()
            
            self.db.collection("users")
                .document(userId)
                .collection("lectures")
                .document(lectureId)
                .setData(docData, merge: true) { error in
                    if let error = error {
                        print("Error saving lecture doc: \(error)")
                    } else {
                        print("Lecture metadata saved to Firestore for \(lectureId)")
                    }
                }
        }
    }
    
    func createFolder(named name: String, folderId: String = UUID().uuidString) {
        guard let userId else {
            print("No userId set on LectureStore; cannot create folder.")
            return
        }
        
        let data: [String: Any] = [
            "name": name,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users")
            .document(userId)
            .collection("folders")
            .document(folderId)
            .setData(data) { error in
                if let error = error {
                    print("Error creating folder: \(error)")
                }
            }
    }
    
    func renameLecture(_ lecture: Lecture, to newTitle: String) {
        var updated = lecture
        updated.title = newTitle
        updateLecture(updated)
        
        guard let userId else { return }
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(["title": newTitle], merge: true) { error in
                if let error = error {
                    print("Error renaming lecture: \(error)")
                }
            }
    }
    
    func moveLecture(_ lecture: Lecture, to folder: Folder?) {
        var updated = lecture
        updated.folderId = folder?.id
        updated.folderName = folder?.name
        updateLecture(updated)
        
        guard let userId else { return }
        
        var data: [String: Any] = [:]
        if let folder {
            data["folderId"] = folder.id
            data["folderName"] = folder.name
        } else {
            data["folderId"] = FieldValue.delete()
            data["folderName"] = FieldValue.delete()
        }
        
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(data, merge: true) { error in
                if let error = error {
                    print("Error moving lecture: \(error)")
                }
            }
    }
    
    func deleteLecture(_ lecture: Lecture) {
        guard let userId else { return }
        
        // Optimistically remove locally
        lectures.removeAll { $0.id == lecture.id }
        
        let docRef = db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
        
        docRef.delete { [weak self] error in
            if let error = error {
                print("Error deleting lecture: \(error)")
            }
        }
        
        // Delete audio blob if present
        if let audioPath = lecture.audioPath {
            storage.reference(withPath: audioPath).delete { error in
                if let error = error {
                    print("Error deleting audio file: \(error)")
                }
            }
        }
    }
}

extension LectureStore {
    static func mockStoreWithSampleData() -> LectureStore {
        LectureStore(seedMockData: true)
    }
}

// MARK: - Duration helpers
private extension LectureStore {
    func durationMinutes(for recordingURL: URL) -> Int? {
        let asset = AVURLAsset(url: recordingURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        return Self.durationMinutes(fromSeconds: CMTimeGetSeconds(asset.duration))
    }
    
    static func durationMinutes(fromSeconds seconds: Double) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return max(1, minutes)
    }
    
    func fillMissingDurationsIfNeeded(for lectures: [Lecture]) {
        for lecture in lectures {
            guard lecture.durationMinutes == nil,
                  let audioPath = lecture.audioPath,
                  !durationFetches.contains(lecture.id) else { continue }
            
            durationFetches.insert(lecture.id)
            
            storage.reference(withPath: audioPath).downloadURL { [weak self] url, error in
                guard let self else { return }
                guard let url else {
                    self.durationFetches.remove(lecture.id)
                    if let error { print("Failed to fetch audio URL for duration: \(error)") }
                    return
                }
                
                let asset = AVURLAsset(url: url, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true
                ])
                
                asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                    guard let self else { return }
                    
                    var loadError: NSError?
                    let status = asset.statusOfValue(forKey: "duration", error: &loadError)
                    guard status == .loaded else {
                        Task { @MainActor in
                            self.durationFetches.remove(lecture.id)
                            if let loadError {
                                print("Failed to load duration for \(lecture.id): \(loadError)")
                            }
                        }
                        return
                    }
                    
                    let minutes = Self.durationMinutes(fromSeconds: CMTimeGetSeconds(asset.duration))
                    Task { @MainActor in
                        self.durationFetches.remove(lecture.id)
                        guard let minutes else { return }
                        self.persistDuration(minutes, for: lecture)
                    }
                }
            }
        }
    }
    
    func persistDuration(_ minutes: Int, for lecture: Lecture) {
        var updated = lecture
        updated.durationMinutes = minutes
        updateLecture(updated)
        
        guard let userId else { return }
        
        db.collection("users")
            .document(userId)
            .collection("lectures")
            .document(lecture.id)
            .setData(["durationMinutes": minutes], merge: true)
    }
}

struct UserUsage {
    let plan: String
    let monthlyMinutesUsed: Int
    let monthlyKey: String?
    let freeLifetimeMinutesUsed: Int
    let periodStart: Date?
    let renewsAt: Date?
    
    var minutesRemaining: Int {
        if plan == "premium" {
            return max(0, 500 - monthlyMinutesUsed)
        } else {
            return max(0, 60 - freeLifetimeMinutesUsed)
        }
    }
}
