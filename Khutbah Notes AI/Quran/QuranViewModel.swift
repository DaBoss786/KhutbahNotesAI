import Foundation
import Combine

final class QuranViewModel: ObservableObject {
    @Published var surahs: [Surah] = []
    @Published var selectedSurah: Surah?
    @Published var verses: [QuranVerse] = []
    @Published var translationOption: QuranTranslationOption = .english
    @Published var isLoading = false
    @Published var loadError: String?

    private let repository: QuranRepository?
    private let workQueue = DispatchQueue(label: "QuranViewModel.queue", qos: .userInitiated)
    private var loadID = 0

    init(repository: QuranRepository? = QuranRepository()) {
        self.repository = repository
        loadInitialData()
    }

    func loadInitialData() {
        guard let repository else {
            loadError = "Quran data is unavailable."
            isLoading = false
            return
        }

        isLoading = true
        loadID += 1
        let currentLoad = loadID
        let includeTranslation = translationOption != .off
        workQueue.async { [weak self] in
            guard let self else { return }
            let surahs = repository.loadSurahs()
            let defaultSurah = surahs.first
            let verses = defaultSurah.map { surah in
                repository.loadVerses(for: surah.id, includeTranslation: includeTranslation)
            } ?? []

            DispatchQueue.main.async {
                guard self.loadID == currentLoad else { return }
                self.surahs = surahs
                self.selectedSurah = defaultSurah
                self.verses = verses
                self.isLoading = false
            }
        }
    }

    func selectSurah(_ surah: Surah) {
        selectedSurah = surah
        reloadVerses()
    }

    @discardableResult
    func selectSurah(id surahId: Int) -> Bool {
        guard let surah = surahs.first(where: { $0.id == surahId }) else {
            return false
        }
        selectSurah(surah)
        return true
    }

    func reloadVerses() {
        guard let repository, let selectedSurah else { return }

        isLoading = true
        loadID += 1
        let currentLoad = loadID
        let includeTranslation = translationOption != .off
        workQueue.async { [weak self] in
            guard let self else { return }
            let verses = repository.loadVerses(for: selectedSurah.id, includeTranslation: includeTranslation)
            DispatchQueue.main.async {
                guard self.loadID == currentLoad else { return }
                self.verses = verses
                self.isLoading = false
            }
        }
    }
}
