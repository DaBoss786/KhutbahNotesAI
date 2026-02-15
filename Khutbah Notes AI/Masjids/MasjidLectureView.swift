import SwiftUI

struct MasjidLectureView: View {
    @EnvironmentObject private var lectureStore: LectureStore
    @EnvironmentObject private var masjidStore: MasjidStore
    @Environment(\.openURL) private var openURL
    let masjid: Masjid
    let khutbah: MasjidKhutbah

    @State private var selectedSummaryLanguage: SummaryTranslationLanguage = .english
    @State private var selectedTextSize: TextSizeOption = .medium
    @State private var selectedContentTab = 0
    @State private var transcriptText: String?
    @State private var isLoadingTranscript = false
    @State private var isSaving = false
    @State private var saveStateMessage: String?

    private let tabs = ["Summary", "Transcript"]

    private var videoId: String? {
        if !khutbah.youtubeVideoId.isEmpty {
            return khutbah.youtubeVideoId
        }
        return YouTubeURLParser.videoId(from: khutbah.youtubeUrl)
    }

    private var summary: LectureSummary? {
        let mainTheme = khutbah.mainTheme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if mainTheme.isEmpty && khutbah.keyPoints.isEmpty && khutbah.weeklyActions.isEmpty {
            return nil
        }
        return LectureSummary(
            mainTheme: mainTheme.isEmpty ? "Not mentioned" : mainTheme,
            keyPoints: khutbah.keyPoints,
            explicitAyatOrHadith: khutbah.explicitAyatOrHadith,
            weeklyActions: khutbah.weeklyActions
        )
    }

    private var dateText: String? {
        guard let date = khutbah.date ?? khutbah.createdAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var youtubeExternalURL: URL? {
        if let parsed = URL(string: khutbah.youtubeUrl),
           let scheme = parsed.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return parsed
        }
        guard let videoId else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoId)")
    }

    private var transcriptBodyFont: Font {
        switch selectedTextSize {
        case .small:
            return .system(size: 14)
        case .medium:
            return .system(size: 16)
        case .large:
            return .system(size: 18)
        case .extraLarge:
            return .system(size: 20)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                playerCard
                if let youtubeExternalURL {
                    Button {
                        openURL(youtubeExternalURL)
                    } label: {
                        Label("Open in YouTube", systemImage: "play.rectangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Theme.primaryGreen)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                PillSegmentedControl(segments: tabs, selection: $selectedContentTab)
                if selectedContentTab == 0 {
                    SummaryView(
                        summary: summary,
                        isBaseSummaryReady: summary != nil,
                        isTranslationLoading: false,
                        translationError: nil,
                        selectedLanguage: $selectedSummaryLanguage,
                        textSize: $selectedTextSize
                    )
                } else {
                    transcriptCard
                }
                saveButton
                if let saveStateMessage {
                    Text(saveStateMessage)
                        .font(.footnote)
                        .foregroundColor(Theme.mutedText)
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Lecture")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: khutbah.id) {
            await loadTranscriptIfNeeded()
        }
        .onChange(of: selectedContentTab) { tab in
            if tab == 1 {
                Task {
                    await loadTranscriptIfNeeded()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(khutbah.title)
                .font(Theme.largeTitleFont)
                .foregroundColor(.black)

            HStack(spacing: 8) {
                Text(masjid.name)
                if let dateText {
                    Text("•")
                    Text(dateText)
                }
                if let speaker = khutbah.speaker, !speaker.isEmpty {
                    Text("•")
                    Text(speaker)
                }
            }
            .font(.caption)
            .foregroundColor(Theme.mutedText)
        }
    }

    @ViewBuilder
    private var playerCard: some View {
        if let videoId {
            YouTubeEmbedView(videoId: videoId, sourceURL: khutbah.youtubeUrl)
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.primaryGreen.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
        } else {
            Text("Unable to load YouTube video.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(14)
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                await saveToNotes()
            }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Image(systemName: "square.and.arrow.down")
                Text(isSaving ? "Saving..." : "Save to Notes")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Theme.primaryGreen, Theme.secondaryGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: Theme.primaryGreen.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .opacity(isSaving ? 0.8 : 1)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Spacer()
                TextSizeToggle(selection: $selectedTextSize, showsBackground: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript")
                    .font(Theme.titleFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Theme.primaryGreen, Theme.secondaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if isLoadingTranscript {
                    HStack(alignment: .center, spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading transcript...")
                            .font(transcriptBodyFont)
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(transcriptText ?? "Transcript will appear here once ready.")
                        .font(transcriptBodyFont)
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
            .padding(.vertical, 4)
        }
    }

    private func loadTranscriptIfNeeded(force: Bool = false) async {
        if isLoadingTranscript {
            return
        }
        if !force,
           let transcriptText,
           !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        isLoadingTranscript = true
        defer { isLoadingTranscript = false }
        transcriptText = await masjidStore.fetchTranscript(for: khutbah)
    }

    private func saveToNotes() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            await loadTranscriptIfNeeded()
            _ = try await lectureStore.saveMasjidKhutbahToNotes(
                masjidName: masjid.name,
                khutbah: khutbah,
                transcriptOverride: transcriptText
            )
            saveStateMessage = "Saved to Notes."
        } catch {
            saveStateMessage = "Could not save. Please try again."
            print("Failed to save masjid khutbah: \(error)")
        }
    }
}
