//
//  NotificationsSettingsView.swift
//  Khutbah Notes AI
//

import SwiftUI
import UIKit
import OneSignalFramework

struct NotificationsSettingsView: View {
    @EnvironmentObject private var store: LectureStore
    @Environment(\.openURL) private var openURL
    @AppStorage("jumuahStartTime") private var storedJumuahStartTime: String?
    @AppStorage("notificationPrefChoice") private var storedNotificationChoice: String?
    @State private var notificationsEnabled = false
    @State private var selectedTime = "12:00"
    @State private var isRequestingPermission = false
    @State private var showPermissionAlert = false
    @State private var hasLoaded = false

    private let times: [String] = [
        "12:00", "12:15", "12:30", "12:45",
        "1:00", "1:15", "1:30", "1:45", "2:00"
    ]

    var body: some View {
        List {
            Section(footer: Text("Turn on reminders before the khutbah and when summaries are ready.")) {
                Toggle("Enable reminders", isOn: $notificationsEnabled)
                    .disabled(isRequestingPermission)
            }

            Section(header: Text("Jumu'ah start time"),
                    footer: Text("Times use your current timezone (\(TimeZone.current.identifier)).")) {
                Picker("Start time", selection: $selectedTime) {
                    ForEach(times, id: \.self) { time in
                        Text(time).tag(time)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            selectedTime = storedJumuahStartTime ?? times.first ?? "12:00"
            notificationsEnabled = (storedNotificationChoice ?? "no") == "push"
            hasLoaded = true
        }
        .onChange(of: notificationsEnabled) { newValue in
            guard hasLoaded else { return }
            if newValue {
                requestNotificationPermission()
            } else {
                storedNotificationChoice = "no"
                Task {
                    await store.saveNotificationPreference("no")
                }
            }
        }
        .onChange(of: selectedTime) { newValue in
            guard hasLoaded else { return }
            storedJumuahStartTime = newValue
            Task {
                await store.saveJumuahStartTime(newValue, timezoneIdentifier: TimeZone.current.identifier)
            }
        }
        .alert("Notifications are off", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable notifications in iOS Settings to receive reminders.")
        }
    }

    private func requestNotificationPermission() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true

        OneSignal.Notifications.requestPermission({ accepted in
            Task {
                let preference = accepted ? "push" : "no"
                storedNotificationChoice = preference
                if accepted {
                    OneSignalIntegration.linkCurrentUser()
                }
                await store.saveNotificationPreference(preference)
                await MainActor.run {
                    isRequestingPermission = false
                    if !accepted {
                        notificationsEnabled = false
                        showPermissionAlert = true
                    }
                }
            }
        }, fallbackToSettings: false)
    }
}
