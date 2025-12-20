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

@available(iOS 16.1, *)
struct OneSignalWidgetAttributes: OneSignalLiveActivityAttributes {
    public struct ContentState: OneSignalLiveActivityContentState {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
        var onesignal: OneSignalLiveActivityContentStateData?
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
    var onesignal: OneSignalLiveActivityAttributeData
}

@available(iOS 16.1, *)
struct OneSignalWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OneSignalWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

@available(iOS 16.1, *)
extension OneSignalWidgetAttributes {
    fileprivate static var preview: OneSignalWidgetAttributes {
        OneSignalWidgetAttributes(
            name: "World",
            onesignal: OneSignalLiveActivityAttributeData.create(activityId: "preview")
        )
    }
}

@available(iOS 16.1, *)
extension OneSignalWidgetAttributes.ContentState {
    fileprivate static var smiley: OneSignalWidgetAttributes.ContentState {
        OneSignalWidgetAttributes.ContentState(emoji: "😀", onesignal: nil)
     }
     
     fileprivate static var starEyes: OneSignalWidgetAttributes.ContentState {
         OneSignalWidgetAttributes.ContentState(emoji: "🤩", onesignal: nil)
     }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Notification", as: .content, using: OneSignalWidgetAttributes.preview) {
   OneSignalWidgetLiveActivity()
} contentStates: {
    OneSignalWidgetAttributes.ContentState.smiley
    OneSignalWidgetAttributes.ContentState.starEyes
}
#endif
