import Foundation

@MainActor
final class RecordingControlCenter {
    static let shared = RecordingControlCenter()

    private let recordingManager = RecordingManager.shared
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
    }

    private func handleResume() {
        recordingManager.resumeRecording()
    }

    private func handleStop(shouldRouteToSaveCard: Bool) {
        _ = recordingManager.stopRecording()
        if shouldRouteToSaveCard {
            RecordingActionStore.setRouteAction(.showSaveCard)
        }
    }
}
