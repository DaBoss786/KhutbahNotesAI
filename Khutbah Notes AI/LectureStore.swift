import SwiftUI
import Combine
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
                        let characterTraits = summaryMap["characterTraits"] as? [String] ?? []
                        let weeklyActions = summaryMap["weeklyActions"] as? [String] ?? []
                        
                        summary = LectureSummary(
                            mainTheme: mainTheme,
                            keyPoints: keyPoints,
                            explicitAyatOrHadith: explicitAyatOrHadith,
                            characterTraits: characterTraits,
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
        
        // Optimistically insert a local lecture while upload happens
        let newLecture = Lecture(
            id: lectureId,
            title: title,
            date: now,
            durationMinutes: nil,
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
            
            let docData: [String: Any] = [
                "title": title,
                "date": Timestamp(date: now),
                "durationMinutes": NSNull(), // can fill later
                "isFavorite": false,
                "status": "processing",
                "transcript": NSNull(),
                "summary": NSNull(),
                "audioPath": audioPath
            ]
            
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
