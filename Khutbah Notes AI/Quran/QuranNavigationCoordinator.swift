import Combine
import Foundation

struct QuranCitationTarget: Identifiable, Equatable {
    let id: UUID
    let surahId: Int
    let ayah: Int

    init(surahId: Int, ayah: Int, id: UUID = UUID()) {
        self.id = id
        self.surahId = surahId
        self.ayah = ayah
    }

    var verseId: String {
        "\(surahId):\(ayah)"
    }
}

@MainActor
final class QuranNavigationCoordinator: ObservableObject {
    @Published var pendingTarget: QuranCitationTarget? = nil

    func requestNavigation(to target: QuranCitationTarget) {
        pendingTarget = target
    }

    func clearPendingTarget() {
        pendingTarget = nil
    }
}
