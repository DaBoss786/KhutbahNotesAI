import SwiftUI

struct AudioRecapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let transcriptAvailable: Bool
    let scope: String
    let initialState: AudioRecapState?
    let onGenerate: (AudioRecapOptions) async -> AudioRecapState
    let onRefresh: (AudioRecapOptions) async -> AudioRecapState

    @State private var options = AudioRecapOptions()
    @State private var recapState: AudioRecapState?
    @State private var isSubmitting = false
    @State private var showRegenerateOptions = false
    @State private var pollTask: Task<Void, Never>?

    private var status: AudioRecapStatus {
        guard transcriptAvailable else { return .unavailable }
        if isSubmitting { return .generating }
        return recapState?.status ?? .missing
    }

    private var canGenerate: Bool {
        transcriptAvailable && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .padding(20)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .recapSheetPresentationStyle()
        .onAppear {
            recapState = initialState
            if recapState == nil {
                Task {
                    await refresh()
                }
            } else {
                updatePolling()
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .onChange(of: recapState?.status) { _ in
            updatePolling()
            if recapState?.status == .ready {
                showRegenerateOptions = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Recap")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                Text(title)
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .missing, .stale:
            setupForm(stale: status == .stale)
        case .generating, .processing:
            generatingView
        case .ready:
            readyView
        case .failed, .unavailable:
            errorView
        }
    }

    private func setupForm(stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if stale {
                Text("Transcript changed since last generation. Regenerate to refresh the recap.")
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
            }
            if !transcriptAvailable {
                Text("Transcript unavailable. Generate transcript first.")
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.mutedText)
                Picker("Voice", selection: $options.voice) {
                    ForEach(AudioRecapVoice.allCases, id: \.self) { voice in
                        Text(voice.label).tag(voice)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Recap style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.mutedText)
                Text("Concise (fixed)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Length")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.mutedText)
                Text("Up to 3 minutes (fixed)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
            }

            Button {
                Task {
                    await generate()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Label("Generate Recap", systemImage: "waveform.badge.mic")
                        .font(.system(size: 15, weight: .semibold))
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
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .opacity(canGenerate ? 1 : 0.6)
        }
    }

    private var generatingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text(recapState?.userMessage ?? "Generating your audio recap...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.mutedText)
            }

            Text("This may take up to a minute.")
                .font(.footnote)
                .foregroundColor(Theme.mutedText)

            Button {
                Task {
                    await refresh()
                }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.primaryGreen)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var readyView: some View {
        if let audioPath = recapState?.audioPath, !audioPath.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LectureAudioPlayerView(
                    audioPath: audioPath,
                    onPlayStarted: {
                        AnalyticsManager.logRecapPlayStarted(
                            scope: scope,
                            variantKey: recapState?.variantKey
                        )
                    }
                )
                if let script = recapState?.script, !script.isEmpty {
                    Text(script)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if showRegenerateOptions {
                    setupForm(stale: false)
                } else {
                    Button {
                        showRegenerateOptions = true
                    } label: {
                        Label("Re-generate audio", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.primaryGreen)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.9))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            errorView
        }
    }

    private var errorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recapState?.userMessage ?? "Could not generate recap. Please try again.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.mutedText)
            Button {
                Task {
                    await generate()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.primaryGreen)
            }
            .buttonStyle(.plain)
            setupForm(stale: false)
        }
    }

    private func generate() async {
        guard canGenerate else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let state = await onGenerate(options)
        recapState = state
        updatePolling()
    }

    private func refresh() async {
        let state = await onRefresh(options)
        recapState = state
        updatePolling()
    }

    private func updatePolling() {
        if status.isInFlight {
            startPollingIfNeeded()
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                let state = await onRefresh(options)
                await MainActor.run {
                    recapState = state
                    if !state.status.isInFlight {
                        pollTask?.cancel()
                        pollTask = nil
                    }
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func recapSheetPresentationStyle() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        } else if #available(iOS 16.0, *) {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
