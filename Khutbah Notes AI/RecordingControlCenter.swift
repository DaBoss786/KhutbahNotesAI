import Foundation

@MainActor
final class RecordingControlCenter {
    static let shared = RecordingControlCenter()

    private let recordingManager = RecordingManager.shared
    private let liveActivityName = "Khutbah recording"

    func handle(_ action: RecordingControlAction, shouldRouteToSaveCard: Bool = false) {
        switch action {
        case .pause:
            handlePause()
        case .resume:
            handleResume()
        case .stop:
            handleStop(shouldRouteToSaveCard: shouldRouteToSaveCard)
        }
    }

    private func handlePause() {
        recordingManager.pauseRecording()
        syncLiveActivity(isPaused: true)
    }

    private func handleResume() {
        recordingManager.resumeRecording()
        syncLiveActivity(isPaused: false)
    }

    private func handleStop(shouldRouteToSaveCard: Bool) {
        let finalElapsed = recordingManager.currentElapsedTime
        _ = recordingManager.stopRecording()
        endLiveActivity(finalElapsed: finalElapsed)
        if shouldRouteToSaveCard {
            RecordingActionStore.setRouteAction(.showSaveCard)
        }
    }

    private func syncLiveActivity(isPaused: Bool) {
        guard recordingManager.isRecording || recordingManager.isPaused else { return }
        guard #available(iOS 16.1, *) else { return }
        let elapsed = recordingManager.currentElapsedTime
        let controller = RecordingLiveActivityController(activityName: liveActivityName)
        controller.startOrUpdate(isPaused: isPaused, elapsed: elapsed)
    }

    private func endLiveActivity(finalElapsed: TimeInterval) {
        guard #available(iOS 16.1, *) else { return }
        let controller = RecordingLiveActivityController(activityName: liveActivityName)
        controller.end(finalElapsed: finalElapsed)
    }
}
