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
    @State private var retryCount = 0
    
    private let maxRetries = 3
    
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
                    .onPurchaseCompleted { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onComplete()
                    }
                    .onRestoreCompleted { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onComplete()
                    }
            } else {
                fallbackView
            }
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
    
    private func loadOffering() async {
        isLoading = true
        loadError = nil
        retryCount = 0
        
        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.offering = offerings.current
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                retryCount += 1
                if retryCount < maxRetries {
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await loadOffering()
                    }
                } else {
                    self.loadError = error
                    self.isLoading = false
                }
            }
        }
    }
}