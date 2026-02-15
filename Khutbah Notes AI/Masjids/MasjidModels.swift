import Foundation
import FirebaseFirestore

struct Masjid: Identifiable, Hashable {
    let id: String
    var name: String
    var city: String
    var state: String?
    var country: String
    var imageUrl: String?
    var lastUpdatedAt: Date?
}

enum MasjidKhutbahStatus: String {
    case queued
    case processing
    case ready
    case error
}

struct MasjidKhutbah: Identifiable, Hashable {
    let id: String
    let masjidId: String
    var youtubeUrl: String
    var youtubeVideoId: String
    var title: String
    var speaker: String?
    var date: Date?
    var durationSec: Int?
    var mainTheme: String?
    var keyPoints: [String]
    var explicitAyatOrHadith: [String]
    var weeklyActions: [String]
    var tags: [String]
    var status: MasjidKhutbahStatus
    var audioPath: String?
    var transcriptRefPath: String?
    var transcriptPreview: String?
    var createdAt: Date?
}
