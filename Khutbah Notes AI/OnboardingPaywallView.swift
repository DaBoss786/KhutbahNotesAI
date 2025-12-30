//
//  OnboardingPaywallView.swift
//  Khutbah Notes AI
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct OnboardingPaywallView: View {
    var onComplete: () -> Void
    
    @State private var offering: Offering?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showActivationConfirmation = false
    @State private var activationError: String?
    @State private var retryCount = 0
    
    private let maxRetries = 3
    private let premiumEntitlementId = "Khutbah Notes Pro"
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if loadError != nil {
                errorView
            } else if let offering = offering {
                PaywallView(offering: offering)
                    .onRequestedDismissal {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onComplete()   // <-- this takes the user to the dashboard in your app
                    }
                    .onPurchaseCompleted {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        handleEntitlementConfirmation(from: $0)
                    }
                    .onRestoreCompleted {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        handleEntitlementConfirmation(from: $0)
                    }

            } else {
                fallbackView
            }

            if showActivationConfirmation {
                activationConfirmationView
                    .transition(.opacity)
            }
        }
        .alert(
            "Unable to confirm Premium",
            isPresented: Binding(
                get: { activationError != nil },
                set: { if !$0 { activationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { activationError = nil }
        } message: {
            Text(activationError ?? "Please try again.")
        }
        .task {
            await loadOffering()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: BrandPalette.cream))
                .scaleEffect(1.2)
            Text("Loading subscription options...")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(BrandPalette.cream.opacity(0.9))
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(BrandPalette.cream.opacity(0.8))
            
            Text("Unable to load subscription options")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(BrandPalette.cream)
                .multilineTextAlignment(.center)
            
            Text("Please check your connection and try again.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(BrandPalette.cream.opacity(0.85))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 14) {
                Button(action: { Task { await loadOffering() } }) {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandPalette.primaryButtonBottom)
                        .padding(.vertical, 16)
                        .background(BrandPalette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                Button(action: { onComplete() }) {
                    Text("Continue without subscribing")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(BrandPalette.cream.opacity(0.8))
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }
    
    private var fallbackView: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(BrandPalette.cream.opacity(0.9))
            
            Text("You're all set!")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(BrandPalette.cream)
            
            Text("Subscription options are not available right now. You can subscribe later from Settings.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(BrandPalette.cream.opacity(0.85))
                .multilineTextAlignment(.center)
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onComplete()
            }) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandPalette.primaryButtonBottom)
                    .padding(.vertical, 16)
                    .background(BrandPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
    }
    
    private var activationConfirmationView: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(BrandPalette.deepGreen.opacity(0.15))
                        .frame(width: 90, height: 90)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(BrandPalette.deepGreen)
                }
                Text("Alhamdulillah - Premium is Active")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(BrandPalette.deepGreen)
                    .multilineTextAlignment(.center)
                Text("You can start recording now!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BrandPalette.deepGreen.opacity(0.85))
                    .multilineTextAlignment(.center)
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showActivationConfirmation = false
                    onComplete()
                }) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandPalette.cream)
                        .padding(.vertical, 14)
                        .background(BrandPalette.deepGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(BrandPalette.cream)
            .cornerRadius(22)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
    
    private func handleEntitlementConfirmation(from info: CustomerInfo) {
        Task { @MainActor in
            activationError = nil
            if hasActivePremiumEntitlement(info) {
                showActivationConfirmation = true
            } else {
                activationError = "We could not confirm Premium yet. Please try Restore Purchases."
            }
        }
    }
    
    private func hasActivePremiumEntitlement(_ info: CustomerInfo) -> Bool {
        if info.entitlements.active[premiumEntitlementId] != nil {
            return true
        }
        if info.entitlements.active.count == 1 {
            print("RevenueCat entitlement mismatch. Active entitlements: \(info.entitlements.active.keys)")
            return true
        }
        return false
    }
    
    private func loadOffering() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
            retryCount = 0
        }
        
        for attempt in 1...maxRetries {
            do {
                let offerings = try await Purchases.shared.offerings()
                await MainActor.run {
                    self.offering = offerings.current
                    self.isLoading = false
                    self.retryCount = attempt - 1
                }
                return
            } catch {
                let delaySeconds = UInt64(attempt) // simple backoff: 1s, 2s, 3s...
                await MainActor.run {
                    self.retryCount = attempt
                }
                
                if attempt == maxRetries {
                    await MainActor.run {
                        self.loadError = error
                        self.isLoading = false
                    }
                    return
                }
                
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }
        
        await MainActor.run { self.isLoading = false }
    }
}
