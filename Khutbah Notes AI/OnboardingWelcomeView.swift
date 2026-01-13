//
//  OnboardingWelcomeView.swift
//  Khutbah Notes AI
//
//  First screen of the onboarding flow.
//

import SwiftUI
import UIKit
import OneSignalFramework

// Analytics: log onboarding_step_viewed on appear/step change (with total count), add Jumu'ah timing details to the next step, and log onboarding_completed on finish.
struct OnboardingFlowView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var step: Step = .welcome
    @State private var hasLoggedInitialStep = false
    @State private var pendingStepDetails: PendingStepDetails?

    private struct PendingStepDetails {
        let jumuahTime: String
        let timezone: String
    }
    
    private enum Step: CaseIterable {
        case welcome
        case rememberEveryKhutbah
        case integrity
        case howItWorks
        case jumuahReminder
        case notificationsPrePrompt
        case paywall
        
        var index: Int {
            switch self {
            case .welcome: return 1
            case .rememberEveryKhutbah: return 2
            case .integrity: return 3
            case .howItWorks: return 4
            case .jumuahReminder: return 5
            case .notificationsPrePrompt: return 6
            case .paywall: return 7
            }
        }

        var analyticsStep: OnboardingStep {
            switch self {
            case .welcome:
                return .welcome
            case .rememberEveryKhutbah:
                return .remember
            case .integrity:
                return .integrity
            case .howItWorks:
                return .howItWorks
            case .jumuahReminder:
                return .jumuahReminder
            case .notificationsPrePrompt:
                return .notificationsPrePrompt
            case .paywall:
                return .paywall
            }
        }
    }
    
    private var totalSteps: Int { Step.allCases.count - 1 } // exclude placeholder
    
    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(progress: progress(for: .welcome)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .rememberEveryKhutbah
                    }
                }
                .transition(.opacity)
            case .rememberEveryKhutbah:
                OnboardingRememberView(progress: progress(for: .rememberEveryKhutbah)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .integrity
                    }
                }
                .transition(.opacity)
            case .integrity:
                OnboardingIntegrityView(progress: progress(for: .integrity)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .howItWorks
                    }
                }
                .transition(.opacity)
            case .howItWorks:
                OnboardingHowItWorksView(progress: progress(for: .howItWorks)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .jumuahReminder
                    }
                }
                .transition(.opacity)
            case .jumuahReminder:
                OnboardingJumuahReminderView(progress: progress(for: .jumuahReminder)) { selection, timezone in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pendingStepDetails = PendingStepDetails(jumuahTime: selection, timezone: timezone)
                        step = .notificationsPrePrompt
                    }
                }
                .transition(.opacity)
            case .notificationsPrePrompt:
                OnboardingNotificationsPrePromptView(progress: progress(for: .notificationsPrePrompt)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .paywall
                    }
                }
                .transition(.opacity)
            case .paywall:
                OnboardingPaywallView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            guard !hasLoggedInitialStep else { return }
            hasLoggedInitialStep = true
            logStepViewed(step)
        }
        .onChange(of: step) { newStep in
            logStepViewed(newStep)
        }
        .onChange(of: hasCompletedOnboarding) { value in
            guard value else { return }
            AnalyticsManager.logOnboardingCompleted(step: step.analyticsStep, totalSteps: totalSteps)
        }
    }
    
    private func progress(for step: Step) -> OnboardingProgress {
        let currentIndex = step.index
        return OnboardingProgress(current: currentIndex, total: totalSteps)
    }

    private func logStepViewed(_ step: Step) {
        let details = step == .notificationsPrePrompt ? pendingStepDetails : nil
        AnalyticsManager.logOnboardingStepViewed(
            step: step.analyticsStep,
            totalSteps: totalSteps,
            jumuahTime: details?.jumuahTime,
            timezone: details?.timezone
        )
        if step == .notificationsPrePrompt {
            pendingStepDetails = nil
        }
    }
}

struct OnboardingRememberView: View {
    let progress: OnboardingProgress
    var onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            BrandPalette.cream
                .ignoresSafeArea()
            
            VStack {
                progressIndicator(progress, background: BrandPalette.cream, foreground: BrandPalette.deepGreen.opacity(0.8))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
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
    let progress: OnboardingProgress
    var onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                progressIndicator(progress, background: .clear, foreground: BrandPalette.cream.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
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

struct OnboardingIntegrityView: View {
    let progress: OnboardingProgress
    var onContinue: () -> Void
    private let contentWidth: CGFloat = 320
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                progressIndicator(progress, background: .clear, foreground: BrandPalette.cream.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
                Spacer()
                
                VStack(alignment: .center, spacing: 18) {
                    Text("Your Khutbah.\nNothing Added.")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.cream)
                        .padding(.bottom, 4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: contentWidth)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        bullet("Uses only YOUR recording")
                        bullet("No fatwas or rulings")
                        bullet("No invented Quran or hadith")
                        bullet("Private & secure")
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    Divider()
                        .background(BrandPalette.cream.opacity(0.35))
                        .padding(.vertical, 10)
                        .frame(maxWidth: contentWidth)
                    
                    Text("Smart summaries never introduce Islamic content that was not said by the khateeb.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(BrandPalette.cream.opacity(0.9))
                        .padding(.top, 2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: contentWidth)
                }
                .padding(.horizontal, 28)
                
                Spacer()
                
                Button(action: handleContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CreamButtonGreenTextStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
    
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(BrandPalette.cream.opacity(0.92))
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundColor(BrandPalette.cream.opacity(0.95))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func handleContinue() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue()
    }
}

struct OnboardingHowItWorksView: View {
    let progress: OnboardingProgress
    var onContinue: () -> Void
    private let contentWidth: CGFloat = 340
    
    var body: some View {
        ZStack {
            BrandPalette.cream
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                progressIndicator(progress, background: BrandPalette.cream, foreground: BrandPalette.deepGreen.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
                Spacer()
                
                VStack(spacing: 22) {
                    Text("How It Works")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.deepGreen)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: contentWidth)
                    
                    VStack(alignment: .leading, spacing: 18) {
                        HowItWorksRow(
                            icon: "mic.circle.fill",
                            title: "Record the khutbah",
                            detail: "Discreetly capture the audio during Jumu'ah."
                        )
                        HowItWorksRow(
                            icon: "list.bullet.rectangle.portrait",
                            title: "Get key takeaways",
                            detail: "Transcriptions, summaries, ayaths, and reminders"
                        )
                        HowItWorksRow(
                            icon: "arrow.clockwise.circle.fill",
                            title: "Reflect all week",
                            detail: "Stay connected to the message beyond Friday."
                        )
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 28)
                
                Spacer()
                
                Button(action: handleContinue) {
                    Text("Continue")
                }
                .buttonStyle(SolidGreenButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
    
    private func handleContinue() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue()
    }
}

struct HowItWorksRow: View {
    var icon: String
    var title: String
    var detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(BrandPalette.deepGreen)
                .frame(width: 42, alignment: .center)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(BrandPalette.deepGreen)
                Text(detail)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(BrandPalette.deepGreen.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private func progressIndicator(_ progress: OnboardingProgress, background: Color, foreground: Color) -> some View {
        OnboardingProgressView(progress: progress, foreground: foreground, background: background)
    }
}

struct OnboardingJumuahReminderView: View {
    let progress: OnboardingProgress
    var onContinue: (_ selectedTime: String, _ timezone: String) -> Void
    
    @EnvironmentObject private var store: LectureStore
    @AppStorage("jumuahStartTime") private var storedJumuahStartTime: String?
    @State private var selectedTime: String?
    
    private let times: [String] = [
        "12:00", "12:15", "12:30", "12:45",
        "1:00", "1:15", "1:30", "1:45", "2:00"
    ]
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                progressIndicator(progress, background: .clear, foreground: BrandPalette.cream.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
                Spacer()
                
                VStack(spacing: 20) {
                    Text("When does your Jumu'ah start?")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.cream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(times, id: \.self) { time in
                            Button(action: { selectedTime = time }) {
                                Text(time)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TimeChipStyle(isSelected: selectedTime == time))
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Text("We'll send you a reminder shortly before the khutbah begins.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(BrandPalette.cream.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                Button(action: handleContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CreamButtonGreenTextStyle())
                .opacity(selectedTime == nil ? 0.6 : 1)
                .disabled(selectedTime == nil)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            selectedTime = storedJumuahStartTime
        }
    }
    
    private func handleContinue() {
        guard let selection = selectedTime else { return }
        storedJumuahStartTime = selection
        let timezone = TimeZone.current.identifier
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        Task {
            await store.saveJumuahStartTime(selection, timezoneIdentifier: timezone)
            await MainActor.run {
                onContinue(selection, timezone)
            }
        }
    }
}

struct TimeChipStyle: ButtonStyle {
    var isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(isSelected ? BrandPalette.deepGreen : BrandPalette.cream)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? BrandPalette.cream : BrandPalette.cream.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BrandPalette.cream.opacity(isSelected ? 0.0 : 0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct OnboardingNotificationsPrePromptView: View {
    let progress: OnboardingProgress
    var onContinue: () -> Void
    
    @EnvironmentObject private var store: LectureStore
    @AppStorage("notificationPrefChoice") private var storedNotificationChoice: String?
    @State private var isRequestingPermission = false
    
    private let contentWidth: CGFloat = 340
    
    var body: some View {
        ZStack {
            BrandPalette.cream
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                progressIndicator(progress, background: BrandPalette.cream, foreground: BrandPalette.deepGreen.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
                Spacer()
                
                VStack(spacing: 20) {
                    Text("Stay Connected Weekly")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundColor(BrandPalette.deepGreen)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: contentWidth)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        reminderBullet("Reminder before khutbah")
                        reminderBullet("Alert when summary is ready")
                        reminderBullet("Midweek reflection reminders")
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 28)
                
                Spacer()
                
                VStack(spacing: 14) {
                    Button(action: handleAllowTapped) {
                        Text("Yes, remind me on Fridays")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SolidGreenButtonStyle())
                    .disabled(isRequestingPermission)
                    
                    Button(action: handleNotNowTapped) {
                        Text("Not now")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(BrandPalette.deepGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .disabled(isRequestingPermission)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }
    
    private func reminderBullet(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(BrandPalette.deepGreen)
                .opacity(0.9)
            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(BrandPalette.deepGreen.opacity(0.95))
        }
    }
    
    private func handleAllowTapped() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        OneSignal.Notifications.requestPermission({ accepted in
            Task {
                let preference = accepted ? "push" : "no"
                let choice: OnboardingNotificationsChoice = accepted ? .push : .no
                AnalyticsManager.logOnboardingNotificationsChoice(
                    choice: choice,
                    step: .notificationsPrePrompt,
                    totalSteps: progress.total
                )
                storedNotificationChoice = preference
                if accepted {
                    OneSignalIntegration.linkCurrentUser()
                }
                
                await store.saveNotificationPreference(preference)
                await MainActor.run {
                    isRequestingPermission = false
                    onContinue()
                }
            }
        }, fallbackToSettings: false)
    }
    
    private func handleNotNowTapped() {
        guard !isRequestingPermission else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let preference = "provisional"
        AnalyticsManager.logOnboardingNotificationsChoice(
            choice: .provisional,
            step: .notificationsPrePrompt,
            totalSteps: progress.total
        )
        storedNotificationChoice = preference
        
        Task {
            await store.saveNotificationPreference(preference)
            await MainActor.run {
                onContinue()
            }
        }
    }
}

struct OnboardingPlaceholderNextView: View {
    var onContinue: () -> Void
    
    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                progressIndicator(OnboardingProgress(current: 6, total: 6), background: .clear, foreground: BrandPalette.cream.opacity(0.75))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                
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
    OnboardingWelcomeView(progress: OnboardingProgress(current: 1, total: 6)) { }
}
