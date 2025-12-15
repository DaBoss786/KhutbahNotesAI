//
//  Khutbah_Notes_AIApp.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import RevenueCat

@main
struct Khutbah_Notes_AIApp: App {
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
}