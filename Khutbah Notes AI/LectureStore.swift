import SwiftUI
import Combine
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class LectureStore: ObservableObject {
    @Published var lectures: [Lecture] = []
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
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
                isFavorite: true,
                status: .ready,
                transcript: nil,
                summary: nil,
                audioPath: nil
            ),
            Lecture(
                id: "mock-2",
                title: "Understanding Taqwa",
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                durationMinutes: 32,
                isFavorite: false,
                status: .processing,
                transcript: nil,
                summary: nil,
                audioPath: nil
            ),
            Lecture(
                id: "mock-3",
                title: "Mercy and Patience",
                date: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                durationMinutes: nil,
                isFavorite: false,
                status: .failed,
                transcript: nil,
                summary: nil,
                audioPath: nil
            )
        ]
    }
    
    func updateLecture(_ lecture: Lecture) {
        guard let index = lectures.firstIndex(where: { $0.id == lecture.id }) else { return }
        lectures[index] = lecture
    }
    
    func start(for userId: String) {
        self.userId = userId
        
        // Stop any previous listener
        listener?.remove()
        
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
                    let isFavorite = data["isFavorite"] as? Bool ?? false
                    let transcript = data["transcript"] as? String
                    let audioPath = data["audioPath"] as? String
                    
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
                    case "ready": status = .ready
                    case "failed": status = .failed
                    default: status = .processing
                    }
                    
                    return Lecture(
                        id: id,
                        title: title,
                        date: date,
                        durationMinutes: durationMinutes,
                        isFavorite: isFavorite,
                        status: status,
                        transcript: transcript,
                        summary: summary,
                        audioPath: audioPath
                    )
                }
                
                self.fillMissingDurationsIfNeeded(for: self.lectures)
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
            isFavorite: false,
            status: .processing,
            transcript: nil,
            summary: nil,
            audioPath: audioPath
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
