import Foundation
import ActivityKit
import OneSignalLiveActivities

@available(iOS 16.1, *)
@MainActor
final class RecordingLiveActivityController {
    static let defaultActivityName = "Khutbah recording"

    private var activity: Activity<OneSignalWidgetAttributes>?
    private let activityId: String
    private let activityName: String

    init(activityName: String, activityId: String = "recording") {
        self.activityName = activityName
        self.activityId = "\(activityId)-\(UUID().uuidString)"
    }

    func startOrUpdate(isPaused: Bool, elapsed: TimeInterval) {
        if activity == nil {
            if attachToExistingActivityIfNeeded() {
                update(isPaused: isPaused, elapsed: elapsed)
            } else {
                start(isPaused: isPaused, elapsed: elapsed)
            }
            return
        }

        update(isPaused: isPaused, elapsed: elapsed)
    }

    func start(isPaused: Bool, elapsed: TimeInterval) {
        guard activity == nil else {
            update(isPaused: isPaused, elapsed: elapsed)
            return
        }

        let onesignalData = OneSignalLiveActivityAttributeData.create(activityId: activityId)
        let attributes = OneSignalWidgetAttributes(name: activityName, onesignal: onesignalData)
        let contentState = makeContentState(isPaused: isPaused, elapsed: elapsed)

        do {
            activity = try Activity<OneSignalWidgetAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: .token
            )
        } catch {
            print("Failed to start recording Live Activity: \(error.localizedDescription)")
        }
    }

    func update(isPaused: Bool, elapsed: TimeInterval) {
        if activity == nil, !attachToExistingActivityIfNeeded() { return }
        guard let activity else { return }
        Task {
            await activity.update(using: makeContentState(isPaused: isPaused, elapsed: elapsed))
        }
    }

    func end(finalElapsed: TimeInterval) {
        let endState = makeContentState(isPaused: true, elapsed: finalElapsed)
        guard let activity else {
            Task {
                for activity in Activity<OneSignalWidgetAttributes>.activities {
                    await activity.end(using: endState, dismissalPolicy: .immediate)
                }
            }
            return
        }
        Task {
            await activity.end(using: endState, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private func makeContentState(isPaused: Bool, elapsed: TimeInterval) -> OneSignalWidgetAttributes.ContentState {
        let startedAt = Date().addingTimeInterval(-elapsed)
        return OneSignalWidgetAttributes.ContentState(
            isPaused: isPaused,
            startedAt: startedAt,
            elapsed: elapsed,
            onesignal: nil
        )
    }

    private func attachToExistingActivityIfNeeded() -> Bool {
        guard activity == nil else { return true }
        guard let existing = Activity<OneSignalWidgetAttributes>.activities.first else { return false }
        activity = existing
        return true
    }
}
