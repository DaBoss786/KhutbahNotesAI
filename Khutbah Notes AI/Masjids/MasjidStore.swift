import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class MasjidStore: ObservableObject {
    @Published private(set) var masjids: [Masjid] = []
    @Published private(set) var khutbahsByMasjid: [String: [MasjidKhutbah]] = [:]
    @Published private(set) var hasLoadedMasjids = false
    @Published private(set) var isAdmin = false
    @Published private(set) var hasCheckedAdminStatus = false
    @Published private(set) var masjidRecapStates: [String: AudioRecapState] = [:]

    private let db = Firestore.firestore()
    private var masjidListener: ListenerRegistration?
    private var khutbahListeners: [String: ListenerRegistration] = [:]
    private var hasStarted = false

    deinit {
        masjidListener?.remove()
        for listener in khutbahListeners.values {
            listener.remove()
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeMasjids()
        Task {
            await refreshAdminStatus()
        }
    }

    func refreshAdminStatus() async {
        do {
            isAdmin = try await MasjidAdminAPI.fetchAdminCapability()
        } catch {
            isAdmin = false
        }
        hasCheckedAdminStatus = true
    }

    func observeKhutbahs(for masjidId: String) {
        guard !masjidId.isEmpty else { return }
        if khutbahListeners[masjidId] != nil {
            return
        }

        let listener = db.collection("masjids")
            .document(masjidId)
            .collection("khutbahs")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Error listening to masjid khutbahs (\(masjidId)): \(error)")
                    return
                }
                guard let docs = snapshot?.documents else {
                    self.khutbahsByMasjid[masjidId] = []
                    return
                }

                let parsed = docs.compactMap { self.parseKhutbah(document: $0, masjidId: masjidId) }
                let readyOnly = parsed.filter { $0.status == .ready }
                let sorted = readyOnly.sorted(by: Self.isKhutbahNewer)
                self.khutbahsByMasjid[masjidId] = sorted
            }

        khutbahListeners[masjidId] = listener
    }

    func khutbahs(for masjidId: String) -> [MasjidKhutbah] {
        khutbahsByMasjid[masjidId] ?? []
    }

    func fetchTranscript(for khutbah: MasjidKhutbah) async -> String? {
        if let transcriptRefPath = khutbah.transcriptRefPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptRefPath.isEmpty {
            do {
                let transcriptDoc = try await db.document(transcriptRefPath).getDocument()
                if let transcriptText = transcriptDoc.data()?["text"] as? String {
                    let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            } catch {
                print("Error loading khutbah transcript (\(khutbah.id)): \(error)")
            }
        }

        if let preview = khutbah.transcriptPreview?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        return nil
    }

    func recapState(masjidId: String, khutbahId: String) -> AudioRecapState? {
        masjidRecapStates[recapStateKey(masjidId: masjidId, khutbahId: khutbahId)]
    }

    @discardableResult
    func requestAudioRecap(
        for khutbah: MasjidKhutbah,
        options: AudioRecapOptions
    ) async -> AudioRecapState {
        let stateKey = recapStateKey(masjidId: khutbah.masjidId, khutbahId: khutbah.id)
        let hasTranscriptHint = (khutbah.transcriptRefPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false) ||
            (khutbah.transcriptPreview?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false)

        if !hasTranscriptHint {
            let unavailable = AudioRecapState.unavailable(
                message: "Transcript unavailable for this lecture.",
                variantKey: ""
            )
            masjidRecapStates[stateKey] = unavailable
            AnalyticsManager.logRecapGenerationFailed(
                scope: "masjid",
                variantKey: nil,
                reason: unavailable.errorMessage
            )
            return unavailable
        }

        AnalyticsManager.logRecapRequest(
            scope: "masjid",
            voice: options.voice.rawValue,
            style: options.style.rawValue,
            lengthSec: options.clampedLengthSec
        )

        do {
            let state = try await AudioRecapAPI.requestMasjidRecap(
                masjidId: khutbah.masjidId,
                khutbahId: khutbah.id,
                options: options
            )
            masjidRecapStates[stateKey] = state
            logRecapState(state, scope: "masjid")
            return state
        } catch {
            let failed = AudioRecapState.unavailable(
                message: error.localizedDescription,
                variantKey: ""
            )
            masjidRecapStates[stateKey] = failed
            AnalyticsManager.logRecapGenerationFailed(
                scope: "masjid",
                variantKey: nil,
                reason: error.localizedDescription
            )
            return failed
        }
    }

    @discardableResult
    func refreshAudioRecap(
        for khutbah: MasjidKhutbah,
        options: AudioRecapOptions
    ) async -> AudioRecapState {
        let stateKey = recapStateKey(masjidId: khutbah.masjidId, khutbahId: khutbah.id)
        do {
            let state = try await AudioRecapAPI.getMasjidRecap(
                masjidId: khutbah.masjidId,
                khutbahId: khutbah.id,
                options: options
            )
            masjidRecapStates[stateKey] = state
            logRecapState(state, scope: "masjid")
            return state
        } catch {
            let failed = AudioRecapState.unavailable(
                message: error.localizedDescription,
                variantKey: ""
            )
            masjidRecapStates[stateKey] = failed
            AnalyticsManager.logRecapGenerationFailed(
                scope: "masjid",
                variantKey: nil,
                reason: error.localizedDescription
            )
            return failed
        }
    }

    private func observeMasjids() {
        masjidListener?.remove()
        hasLoadedMasjids = false

        masjidListener = db.collection("masjids")
            .order(by: "name")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Error listening to masjids: \(error)")
                    self.hasLoadedMasjids = true
                    return
                }

                guard let documents = snapshot?.documents else {
                    self.masjids = []
                    self.hasLoadedMasjids = true
                    return
                }

                self.masjids = documents.map(self.parseMasjid(document:))
                self.hasLoadedMasjids = true
            }
    }

    private func parseMasjid(document: QueryDocumentSnapshot) -> Masjid {
        let data = document.data()
        return Masjid(
            id: document.documentID,
            name: data["name"] as? String ?? "Unknown Masjid",
            city: data["city"] as? String ?? "",
            state: data["state"] as? String,
            country: data["country"] as? String ?? "",
            imageUrl: data["imageUrl"] as? String,
            lastUpdatedAt: (data["lastUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }

    private func parseKhutbah(document: QueryDocumentSnapshot, masjidId: String) -> MasjidKhutbah? {
        let data = document.data()
        guard let rawStatus = data["status"] as? String,
              let status = MasjidKhutbahStatus(rawValue: rawStatus) else {
            return nil
        }

        return MasjidKhutbah(
            id: document.documentID,
            masjidId: masjidId,
            youtubeUrl: data["youtubeUrl"] as? String ?? "",
            youtubeVideoId: data["youtubeVideoId"] as? String ?? "",
            title: data["title"] as? String ?? "Untitled Khutbah",
            speaker: data["speaker"] as? String,
            date: (data["date"] as? Timestamp)?.dateValue(),
            durationSec: data["durationSec"] as? Int,
            mainTheme: data["mainTheme"] as? String,
            keyPoints: data["keyPoints"] as? [String] ?? [],
            explicitAyatOrHadith: data["explicitAyatOrHadith"] as? [String] ?? [],
            weeklyActions: data["weeklyActions"] as? [String] ?? [],
            tags: data["tags"] as? [String] ?? [],
            status: status,
            audioPath: data["audioPath"] as? String,
            transcriptRefPath: data["transcriptRefPath"] as? String,
            transcriptPreview: data["transcriptPreview"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func isKhutbahNewer(_ lhs: MasjidKhutbah, _ rhs: MasjidKhutbah) -> Bool {
        let lhsDate = lhs.date ?? lhs.createdAt ?? .distantPast
        let rhsDate = rhs.date ?? rhs.createdAt ?? .distantPast
        return lhsDate > rhsDate
    }

    private func recapStateKey(masjidId: String, khutbahId: String) -> String {
        "\(masjidId)#\(khutbahId)"
    }

    private func logRecapState(_ state: AudioRecapState, scope: String) {
        switch state.status {
        case .generating, .processing:
            AnalyticsManager.logRecapGenerationStarted(
                scope: scope,
                variantKey: state.variantKey.isEmpty ? nil : state.variantKey
            )
        case .ready:
            AnalyticsManager.logRecapGenerationSucceeded(
                scope: scope,
                variantKey: state.variantKey.isEmpty ? nil : state.variantKey,
                durationSec: state.durationSec
            )
        case .failed, .unavailable:
            AnalyticsManager.logRecapGenerationFailed(
                scope: scope,
                variantKey: state.variantKey.isEmpty ? nil : state.variantKey,
                reason: state.errorMessage
            )
        case .missing, .stale:
            break
        }
    }
}
