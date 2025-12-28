//
//  OneSignalWidgetLiveActivity.swift
//  OneSignalWidget
//
//  Created by Abbas Anwar on 12/19/25.
//

import ActivityKit
import WidgetKit
import SwiftUI
import OneSignalLiveActivities
import AppIntents

@available(iOS 16.1, *)
struct OneSignalWidgetAttributes: OneSignalLiveActivityAttributes {
    public struct ContentState: OneSignalLiveActivityContentState {
        var isPaused: Bool
        var startedAt: Date
        var elapsed: TimeInterval
        var onesignal: OneSignalLiveActivityContentStateData?
    }

    var name: String
    var onesignal: OneSignalLiveActivityAttributeData
}

@available(iOS 16.1, *)
struct OneSignalWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OneSignalWidgetAttributes.self) { context in
            let isPaused = context.state.isPaused
            let statusColor = isPaused ? LiveActivityColors.pauseAccent : LiveActivityColors.brandGreen
            let elapsedText = elapsedString(context.state.elapsed)
            let displayDate = context.state.startedAt

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image("KhutbahNotesLogoSmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Khutbah Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(LiveActivityColors.brandGreen)
                        .textCase(.uppercase)
                        .tracking(1.0)
                    Spacer()
                    Text(isPaused ? "Paused" : "Recording")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isPaused ? LiveActivityColors.pausePill : LiveActivityColors.recordPill)
                        )
                }

                Group {
                    if isPaused {
                        Text(elapsedText)
                    } else {
                        Text(displayDate, style: .timer)
                    }
                }
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(LiveActivityColors.deepGreen)

                if #available(iOS 17.0, *) {
                    LiveActivityControls(isPaused: isPaused)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .activityBackgroundTint(LiveActivityColors.lockScreenBackground)
            .activitySystemActionForegroundColor(.white)
            .recordingWidgetLink()
        } dynamicIsland: { context in
            let isPaused = context.state.isPaused
            let statusColor = isPaused ? LiveActivityColors.pauseAccent : LiveActivityColors.brandGreen
            let elapsedText = elapsedString(context.state.elapsed)
            let displayDate = context.state.startedAt

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("KhutbahNotesLogoSmall")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text("Khutbah Notes")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(LiveActivityColors.brandGreen)
                            .textCase(.uppercase)
                            .tracking(1.0)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Group {
                        if isPaused {
                            Text(elapsedText)
                        } else {
                            Text(displayDate, style: .timer)
                        }
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(LiveActivityColors.deepGreen)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(isPaused ? "Paused" : "Recording")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isPaused ? LiveActivityColors.pausePill : LiveActivityColors.recordPill)
                            )

                        if #available(iOS 17.0, *) {
                            LiveActivityControls(isPaused: isPaused)
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                Group {
                    if isPaused {
                        Text(elapsedString(context.state.elapsed, compact: true))
                    } else {
                        Text(displayDate, style: .timer)
                    }
                }
                .monospacedDigit()
            } minimal: {
                Image(systemName: isPaused ? "pause.fill" : "mic.fill")
                    .foregroundColor(statusColor)
            }
            .keylineTint(statusColor)
            .recordingWidgetLink()
        }
    }
}

@available(iOS 16.1, *)
extension OneSignalWidgetAttributes {
    fileprivate static var preview: OneSignalWidgetAttributes {
        OneSignalWidgetAttributes(
            name: "Khutbah recording",
            onesignal: OneSignalLiveActivityAttributeData.create(activityId: "preview")
        )
    }
}

@available(iOS 16.1, *)
extension OneSignalWidgetAttributes.ContentState {
    fileprivate static var recording: OneSignalWidgetAttributes.ContentState {
        OneSignalWidgetAttributes.ContentState(
            isPaused: false,
            startedAt: Date().addingTimeInterval(-85),
            elapsed: 85,
            onesignal: nil
        )
    }
    
    fileprivate static var paused: OneSignalWidgetAttributes.ContentState {
        OneSignalWidgetAttributes.ContentState(
            isPaused: true,
            startedAt: Date().addingTimeInterval(-420),
            elapsed: 420,
            onesignal: nil
        )
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Notification", as: .content, using: OneSignalWidgetAttributes.preview) {
   OneSignalWidgetLiveActivity()
} contentStates: {
    OneSignalWidgetAttributes.ContentState.recording
    OneSignalWidgetAttributes.ContentState.paused
}
#endif

@available(iOS 16.1, *)
private func elapsedString(_ elapsed: TimeInterval, compact: Bool = false) -> String {
    let totalSeconds = max(0, Int(elapsed.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if compact && hours == 0 {
        return String(format: "%02d:%02d", minutes, seconds)
    }

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%02d:%02d", minutes, seconds)
}

private enum LiveActivityColors {
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let deepGreen = Color(red: 0.07, green: 0.36, blue: 0.25)
    static let mutedGreen = Color(red: 0.07, green: 0.36, blue: 0.25).opacity(0.6)
    static let brandGreen = Color(red: 0.13, green: 0.61, blue: 0.39)
    static let pauseAccent = Color(red: 0.87, green: 0.55, blue: 0.20)
    static let stopAccent = Color(red: 0.70, green: 0.20, blue: 0.18)
    static let lockScreenBackground = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let recordPill = Color(red: 0.20, green: 0.31, blue: 0.30)
    static let pausePill = Color(red: 0.33, green: 0.25, blue: 0.18)
}

@available(iOS 17.0, *)
private struct LiveActivityControls: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isPaused {
                LiveActivityControlButton(
                    intent: ResumeRecordingIntent(),
                    title: "Resume",
                    systemImage: "play.fill",
                    tint: LiveActivityColors.brandGreen
                )
            } else {
                LiveActivityControlButton(
                    intent: PauseRecordingIntent(),
                    title: "Pause",
                    systemImage: "pause.fill",
                    tint: LiveActivityColors.pauseAccent
                )
            }

            LiveActivityControlButton(
                intent: StopRecordingIntent(),
                title: "Stop",
                systemImage: "stop.fill",
                tint: LiveActivityColors.stopAccent
            )
        }
        .controlSize(.small)
    }
}

@available(iOS 17.0, *)
private struct LiveActivityControlButton<Intent: AppIntent>: View {
    let intent: Intent
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
        }
        .font(.caption2.weight(.semibold))
        .tint(tint)
        .buttonStyle(.borderedProminent)
    }
}

private let recordingDeepLinkURL = URL(string: "khutbahnotesai://recording?action=openRecording")!

@available(iOS 16.1, *)
private extension View {
    @ViewBuilder
    func recordingWidgetLink() -> some View {
        if #available(iOS 17.0, *) {
            self
        } else {
            self.widgetURL(recordingDeepLinkURL)
        }
    }
}

@available(iOS 16.1, *)
private extension DynamicIsland {
    func recordingWidgetLink() -> DynamicIsland {
        if #available(iOS 17.0, *) {
            return self
        }
        return widgetURL(recordingDeepLinkURL)
    }
}

@available(iOS 17.0, *)
private enum WidgetRecordingControlAction: String {
    case pause
    case resume
    case stop
}

@available(iOS 17.0, *)
private enum WidgetRecordingUserDefaultsKeys {
    static let appGroup = "group.com.medswipeapp.Khutbah-Notes-AI.onesignal"
    static let controlAction = "recordingControlAction"
}

@available(iOS 17.0, *)
private enum WidgetRecordingUserDefaults {
    static let shared: UserDefaults = UserDefaults(suiteName: WidgetRecordingUserDefaultsKeys.appGroup) ?? .standard
}

@available(iOS 17.0, *)
private func storeControlAction(_ action: WidgetRecordingControlAction) {
    WidgetRecordingUserDefaults.shared.set(action.rawValue, forKey: WidgetRecordingUserDefaultsKeys.controlAction)
}

@available(iOS 17.0, *)
struct PauseRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Recording"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        storeControlAction(.pause)
        return .result()
    }
}

@available(iOS 17.0, *)
struct ResumeRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Recording"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        storeControlAction(.resume)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        storeControlAction(.stop)
        return .result()
    }
}
