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
import RevenueCat
import OneSignalFramework

private let oneSignalAppId = "290aa0ce-8c6c-4e7d-84c1-914fbdac66f1" // TODO: replace with your OneSignal App ID
private let isOneSignalConfigured = !oneSignalAppId.isEmpty

@main
struct Khutbah_Notes_AIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: LectureStore
    @State private var showSplash = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    init() {
        FirebaseApp.configure()
        
        // Configure RevenueCat
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_idynIRrxuwivElFlKBywbHYCVzs")
        
        let lectureStore = LectureStore(seedMockData: true)
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
            }
            .environmentObject(store)
        }
    }
    
    private func signInAnonymouslyIfNeeded(using store: LectureStore) {
        if let user = Auth.auth().currentUser {
            print("Firebase already signed in with uid: \(user.uid)")
            syncRevenueCatUser(with: user.uid)
            linkOneSignalUser(with: user.uid)
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
                self.syncRevenueCatUser(with: user.uid)
                self.linkOneSignalUser(with: user.uid)
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
    
    private func linkOneSignalUser(with userId: String) {
        guard isOneSignalConfigured else {
            print("OneSignal App ID not set; skipping OneSignal login.")
            return
        }
        
        OneSignal.login(userId)
        
        persistOneSignalIdentifiers(
            subscriptionId: OneSignal.User.pushSubscription.id,
            onesignalId: OneSignal.User.onesignalId
        )
    }
}

func persistOneSignalIdentifiers(subscriptionId: String?, onesignalId: String?) {
    var oneSignalData: [String: Any] = [:]
    
    if let onesignalId, !onesignalId.isEmpty {
        oneSignalData["oneSignalId"] = onesignalId
    } else {
        print("OneSignal ID not available yet; will try again on next launch.")
    }
    
    if let subscriptionId, !subscriptionId.isEmpty {
        oneSignalData["pushSubscriptionId"] = subscriptionId
    } else {
        print("OneSignal push subscription ID not available yet; will try again on next launch.")
    }
    
    guard
        let currentUid = Auth.auth().currentUser?.uid,
        !oneSignalData.isEmpty
    else { return }
    
    Firestore.firestore().collection("users").document(currentUid).setData(["oneSignal": oneSignalData], merge: true) { error in
        if let error {
            print("Failed to save OneSignal identifiers to Firestore: \(error.localizedDescription)")
        } else {
            print("Saved OneSignal identifiers for user \(currentUid)")
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OneSignal.Debug.setLogLevel(.LL_VERBOSE) // Remove or lower log level in production
        OneSignal.initialize(oneSignalAppId, withLaunchOptions: launchOptions)
        return true
    }
}
