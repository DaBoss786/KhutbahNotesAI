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

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image("KhutbahNotesLogoSmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(LiveActivityColors.logoOutline, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Khutbah Notes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(LiveActivityColors.deepGreen)

                        LiveActivityStatusLabel(isPaused: isPaused)
                    }

                    Spacer()

                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LiveActivityColors.mutedGreen)
                }

                if #available(iOS 17.0, *) {
                    HStack(spacing: 12) {
                        LiveActivityTimerView(isPaused: isPaused, elapsedText: elapsedText, displayDate: displayDate)
                        Spacer(minLength: 8)
                        LiveActivityControls(isPaused: isPaused, layout: .lockScreen)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LiveActivityColors.controlBackground)
                    )
                } else {
                    HStack {
                        Spacer()
                        LiveActivityTimerView(isPaused: isPaused, elapsedText: elapsedText, displayDate: displayDate)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LiveActivityColors.controlBackground)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(14)
            .activityBackgroundTint(LiveActivityColors.lockScreenBackground)
            .activitySystemActionForegroundColor(LiveActivityColors.deepGreen)
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
                    LiveActivityTimerView(isPaused: isPaused, elapsedText: elapsedText, displayDate: displayDate)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        LiveActivityStatusLabel(isPaused: isPaused)

                        if #available(iOS 17.0, *) {
                            LiveActivityControls(isPaused: isPaused, layout: .dynamicIsland)
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
    static let recordingDot = Color(red: 0.85, green: 0.25, blue: 0.22)
    static let pauseAccent = Color(red: 0.87, green: 0.55, blue: 0.20)
    static let stopAccent = Color(red: 0.70, green: 0.20, blue: 0.18)
    static let lockScreenBackground = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let controlBackground = Color(red: 0.91, green: 0.98, blue: 0.94)
    static let logoOutline = Color(red: 0.87, green: 0.92, blue: 0.88)
    static let recordPill = Color(red: 0.20, green: 0.31, blue: 0.30)
    static let pausePill = Color(red: 0.33, green: 0.25, blue: 0.18)
}

@available(iOS 17.0, *)
private struct LiveActivityControls: View {
    let isPaused: Bool
    let layout: LiveActivityControlLayout

    var body: some View {
        HStack(spacing: layout.spacing) {
            if isPaused {
                LiveActivityControlButton(
                    intent: ResumeRecordingIntent(),
                    title: "Resume",
                    systemImage: "play.fill",
                    tint: LiveActivityColors.brandGreen,
                    layout: layout
                )
            } else {
                LiveActivityControlButton(
                    intent: PauseRecordingIntent(),
                    title: "Pause",
                    systemImage: "pause.fill",
                    tint: LiveActivityColors.pauseAccent,
                    layout: layout
                )
            }

            LiveActivityControlButton(
                intent: StopRecordingIntent(),
                title: "Stop",
                systemImage: "stop.fill",
                tint: LiveActivityColors.stopAccent,
                layout: layout
            )
        }
    }
}

@available(iOS 17.0, *)
private struct LiveActivityControlButton<Intent: AppIntent>: View {
    let intent: Intent
    let title: String
    let systemImage: String
    let tint: Color
    let layout: LiveActivityControlLayout

    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
                .font(layout.font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
                .foregroundColor(.white)
                .background(
                    Capsule()
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 17.0, *)
private enum LiveActivityControlLayout {
    case lockScreen
    case dynamicIsland

    var font: Font {
        switch self {
        case .lockScreen:
            return .footnote.weight(.semibold)
        case .dynamicIsland:
            return .caption2.weight(.semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .lockScreen:
            return 14
        case .dynamicIsland:
            return 10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .lockScreen:
            return 8
        case .dynamicIsland:
            return 6
        }
    }

    var spacing: CGFloat {
        switch self {
        case .lockScreen:
            return 10
        case .dynamicIsland:
            return 8
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityStatusLabel: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isPaused {
                Circle()
                    .fill(LiveActivityColors.pauseAccent)
                    .frame(width: 8, height: 8)
            } else {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(phase * 2.0 * .pi * 0.8) + 1) / 2
                    let scale = 0.85 + (0.25 * pulse)
                    let opacity = 0.55 + (0.45 * pulse)

                    Circle()
                        .fill(LiveActivityColors.recordingDot)
                        .frame(width: 8, height: 8)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
            Text(isPaused ? "Paused" : "Recording")
                .font(.footnote.weight(.semibold))
                .foregroundColor(LiveActivityColors.mutedGreen)
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityTimerView: View {
    let isPaused: Bool
    let elapsedText: String
    let displayDate: Date

    var body: some View {
        Group {
            if isPaused {
                Text(elapsedText)
            } else {
                Text(displayDate, style: .timer)
            }
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundColor(LiveActivityColors.deepGreen)
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
