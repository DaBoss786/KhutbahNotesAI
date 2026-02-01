//
//  Khutbah_Notes_AIApp.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics
import RevenueCat
import OneSignalFramework
import OneSignalLiveActivities

@main
struct Khutbah_Notes_AIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: LectureStore
    @State private var showSplash = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("pendingRamadanGiftModal") private var pendingRamadanGiftModal = false
    @AppStorage("hasShownRamadanGiftModal") private var hasShownRamadanGiftModal = false
    
    init() {
        FirebaseApp.configure()
        AnalyticsManager.configure()
        
        // Configure RevenueCat
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_idynIRrxuwivElFlKBywbHYCVzs")
        
        let lectureStore = LectureStore()
        _store = StateObject(wrappedValue: lectureStore)
        signInAnonymouslyIfNeeded(using: lectureStore)
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .opacity((showSplash || !hasCompletedOnboarding) ? 0 : 1)
                
                if !hasCompletedOnboarding && !showSplash {
                    OnboardingFlowView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .transition(.opacity)
                }
                
                if showSplash {
                    SplashView(isActive: $showSplash)
                        .transition(.opacity)
                }

                if shouldShowRamadanGiftModal {
                    RamadanGiftModalView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            pendingRamadanGiftModal = false
                            hasShownRamadanGiftModal = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .environmentObject(store)
            .onOpenURL { url in
                if DashboardDeepLink.matches(url) {
                    DashboardDeepLinkStore.setPendingDashboard()
                    return
                }
                if let target = QuranDeepLink.target(from: url) {
                    QuranDeepLinkStore.setPendingTarget(target)
                    AnalyticsManager.logWidgetTapOpenVerse()
                    return
                }
                if let lectureId = LectureDeepLink.lectureId(from: url) {
                    LectureDeepLinkStore.setPendingLectureId(lectureId)
                    return
                }
                if let action = RecordingDeepLink.action(from: url) {
                    if action == .openRecording {
                        AnalyticsManager.logWidgetTapOpenRecordFriday()
                    }
                    RecordingActionStore.setRouteAction(action)
                }
            }
        }
    }
    
    private func signInAnonymouslyIfNeeded(using store: LectureStore) {
        if let user = Auth.auth().currentUser {
            print("Firebase already signed in with uid: \(user.uid)")
            AnalyticsManager.setUserId(user.uid)
            syncRevenueCatUser(with: user.uid)
            OneSignalIntegration.linkCurrentUser(with: user.uid)
            store.start(for: user.uid)
            return
        }
        
        Auth.auth().signInAnonymously { result, error in
            if let error {
                print("Anonymous sign-in failed: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user else {
                print("Anonymous sign-in returned no user.")
                return
            }
            
            print("Signed in anonymously with uid: \(user.uid)")
            DispatchQueue.main.async {
                AnalyticsManager.setUserId(user.uid)
                self.syncRevenueCatUser(with: user.uid)
                OneSignalIntegration.linkCurrentUser(with: user.uid)
                self.store.start(for: user.uid)
            }
        }
    }
    
    private func syncRevenueCatUser(with userId: String) {
        Purchases.shared.logIn(userId) { _, _, error in
            if let error {
                print("RevenueCat logIn failed: \(error.localizedDescription)")
            } else {
                print("RevenueCat synced with user: \(userId)")
            }
        }
    }

    private var shouldShowRamadanGiftModal: Bool {
        pendingRamadanGiftModal && !showSplash && hasCompletedOnboarding && !hasShownRamadanGiftModal
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OneSignalIntegration.configureIfNeeded()
        OneSignalIntegration.registerNotificationClickHandler()
        if #available(iOS 16.1, *) {
            OneSignal.LiveActivities.setup(OneSignalWidgetAttributes.self)
        }
        return true
    }
}
