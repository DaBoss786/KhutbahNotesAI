import AVKit
import Combine
import SwiftUI

enum WidgetInstructionsSource: String {
    case settings
    case banner
}

struct WidgetInstructionsView: View {
    let source: WidgetInstructionsSource
    @AppStorage("isPresentingWidgetInstructions") private var isPresentingWidgetInstructions = false
    @StateObject private var videoPlayer = LoopingVideoPlayer(
        resourceName: "Lock Screen",
        resourceExtension: "mp4"
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                stepsSection
                tipsSection
                videoSection
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Lock Screen Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isPresentingWidgetInstructions = true
            videoPlayer.play()
        }
        .onDisappear {
            isPresentingWidgetInstructions = false
            videoPlayer.pause()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add an ayah to your lock screen")
                .font(Theme.largeTitleFont)
                .foregroundColor(.black)
            Text("On Fridays (11:30am–2pm), it becomes a quick Jummah recorder.")
                .font(.subheadline)
                .foregroundColor(Theme.mutedText)
        }
    }

    private var videoWidth: CGFloat {
        // Keep the preview phone-sized and centered, even on wider screens.
        let horizontalPadding: CGFloat = 32 // Matches the outer horizontal padding.
        let availableWidth = max(UIScreen.main.bounds.width - horizontalPadding, 0)
        return min(availableWidth, 280)
    }

    private var videoHeight: CGFloat {
        // Target a tall 9:16 presentation so the phone screen appears larger.
        let height = videoWidth * 16.0 / 9.0
        return min(height, 440)
    }

    @ViewBuilder
    private var videoSection: some View {
        if let player = videoPlayer.player {
            HStack {
                Spacer(minLength: 0)
                VideoPlayer(player: player)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(width: videoWidth, height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.primaryGreen.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Theme.shadow, radius: 10, x: 0, y: 6)
                Spacer(minLength: 0)
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Video unavailable")
                        .font(.headline)
                        .foregroundColor(.black)
                    Text("You can still follow the steps below.")
                        .font(.subheadline)
                        .foregroundColor(Theme.mutedText)
                }
                .padding(16)
                .frame(width: videoWidth, alignment: .leading)
                .background(Theme.cardBackground)
                .cornerRadius(16)
                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                Spacer(minLength: 0)
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to add it")
                .font(Theme.titleFont)
                .foregroundColor(.black)

            InstructionStepCard(
                number: 1,
                title: "Press and hold your Lock Screen",
                detail: "Tap Customize."
            )
            InstructionStepCard(
                number: 2,
                title: "Tap the widget area",
                detail: "In the widget picker, find Khutbah Notes."
            )
            InstructionStepCard(
                number: 3,
                title: "Select Daily or Hourly Ayah",
                detail: "Add the rectangular widget you prefer and tap Done."
            )
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tip")
                .font(.headline)
                .foregroundColor(.black)
            Text("If you don’t see the widget, lock your phone and try again. iOS sometimes needs a moment after installing an update.")
                .font(.subheadline)
                .foregroundColor(Theme.mutedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}

private struct InstructionStepCard: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.primaryGreen.opacity(0.14))
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.primaryGreen)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}

private final class LoopingVideoPlayer: ObservableObject {
    @Published var player: AVPlayer? = nil

    private var endObserver: NSObjectProtocol?
    private var loopWorkItem: DispatchWorkItem?
    private var isLoopScheduled = false
    private let notificationCenter: NotificationCenter
    private let loopDelay: TimeInterval

    init(
        resourceName: String,
        resourceExtension: String,
        bundle: Bundle = .main,
        notificationCenter: NotificationCenter = .default,
        loopDelay: TimeInterval = 3.0
    ) {
        self.notificationCenter = notificationCenter
        self.loopDelay = loopDelay

        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            return
        }

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        self.player = player

        endObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            self.scheduleNextLoop(for: player)
        }
    }

    deinit {
        loopWorkItem?.cancel()
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
        }
    }

    func play() {
        loopWorkItem?.cancel()
        loopWorkItem = nil
        isLoopScheduled = false
        player?.seek(to: .zero)
        player?.play()
    }

    func pause() {
        loopWorkItem?.cancel()
        loopWorkItem = nil
        isLoopScheduled = false
        player?.pause()
    }

    private func scheduleNextLoop(for player: AVPlayer) {
        guard !isLoopScheduled else { return }
        isLoopScheduled = true
        player.pause()

        let workItem = DispatchWorkItem { [weak self, weak player] in
            guard let self, let player else { return }
            self.isLoopScheduled = false
            player.seek(to: .zero)
            player.play()
        }
        loopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loopDelay, execute: workItem)
    }
}
