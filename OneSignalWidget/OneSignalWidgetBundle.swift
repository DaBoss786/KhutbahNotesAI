//
//  OneSignalWidgetBundle.swift
//  OneSignalWidget
//
//  Created by Abbas Anwar on 12/19/25.
//

import WidgetKit
import SwiftUI

@main
struct OneSignalWidgetBundle: WidgetBundle {
    var body: some Widget {
        OneSignalWidget()
        OneSignalWidgetControl()
        OneSignalWidgetLiveActivity()
        DailyAyahWidget()
    }
}
