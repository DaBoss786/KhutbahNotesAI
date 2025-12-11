//
//  OnboardingWelcomeView.swift
//  Khutbah Notes AI
//
//  First screen of the onboarding flow.
//

import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var step: Step = .welcome
    
    private enum Step {
        case welcome
        case rememberEveryKhutbah
        case nextPlaceholder
    }
    
    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .rememberEveryKhutbah
                    }
                }
                .transition(.opacity)
            case .rememberEveryKhutbah:
                OnboardingRememberView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .nextPlaceholder
                    }
                }
                .transition(.opacity)
            case .nextPlaceholder:
                OnboardingPlaceholderNextView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct OnboardingRememberView: View {
    var onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            BrandPalette.cream
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                VStack(spacing: 22) {
                    Text("Remember Every\nKhutbah")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.deepGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text("Record, summarize, and reflect on\nFriday sermons—safely and privately.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(BrandPalette.deepGreen)
                        .padding(.top, 10)
                }
                
                Spacer()
                
                Button(action: handleGetStarted) {
                    Text("Continue")
                }
                .buttonStyle(SolidGreenButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
    
    private func handleGetStarted() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGetStarted()
    }
}

struct OnboardingWelcomeView: View {
    var onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer(minLength: 10)
                
                Text("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundColor(BrandPalette.cream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                VStack(spacing: 10) {
                    Text("Assalamu alaikum")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundColor(BrandPalette.cream.opacity(0.94))
                    
                    Text("Welcome to Khutbah Notes")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.cream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text("A simple way to remember and\nreflect on khutbahs and lectures")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(BrandPalette.cream.opacity(0.94))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
        Button(action: handleGetStarted) {
            Text("Get Started")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CreamButtonGreenTextStyle())
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }
}
    }
    
    private func handleGetStarted() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGetStarted()
    }
}

struct OnboardingPlaceholderNextView: View {
    var onContinue: () -> Void
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Spacer()
                
                Text("Onboarding, continued")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(BrandPalette.cream)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
                
                Text("Swap this screen with your next onboarding step when it's ready.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(BrandPalette.cream.opacity(0.94))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                
                Spacer()
                
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SolidGreenButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
}

struct CreamButtonGreenTextStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(BrandPalette.primaryButtonBottom)
            .padding(.vertical, 16)
            .background(
                BrandPalette.cream
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SolidGreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(BrandPalette.cream)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [BrandPalette.deepGreen, BrandPalette.gradientBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingWelcomeView { }
}
