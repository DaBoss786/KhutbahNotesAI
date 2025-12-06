import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class LectureStore: ObservableObject {
    @Published var lectures: [Lecture] = []
    private var recordingURLs: [String: URL] = [:]
    private var db: Firestore?
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
                summary: nil
            ),
            Lecture(
                id: "mock-2",
                title: "Understanding Taqwa",
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                durationMinutes: 32,
                isFavorite: false,
                status: .processing,
                transcript: nil,
                summary: nil
            ),
            Lecture(
                id: "mock-3",
                title: "Mercy and Patience",
                date: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                durationMinutes: nil,
                isFavorite: false,
                status: .failed,
                transcript: nil,
                summary: nil
            )
        ]
    }
    
    func addLecture(_ lecture: Lecture) {
        lectures.append(lecture)
    }
    
    func attachRecordingURL(_ url: URL, to lectureId: String) {
        recordingURLs[lectureId] = url
    }
    
    func updateLecture(_ lecture: Lecture) {
        guard let index = lectures.firstIndex(where: { $0.id == lecture.id }) else { return }
        lectures[index] = lecture
    }
    
    func start(for userId: String) {
        self.userId = userId
        db = Firestore.firestore()
    }
}

extension LectureStore {
    static func mockStoreWithSampleData() -> LectureStore {
        LectureStore(seedMockData: true)
    }
}
