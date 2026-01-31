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
    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(progress: progress(for: .welcome)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .rememberEveryKhutbah
                    }
                }
                .transition(stepTransition)
            case .rememberEveryKhutbah:
                OnboardingRememberView(progress: progress(for: .rememberEveryKhutbah)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .integrity
                    }
                }
                .transition(stepTransition)
            case .integrity:
                OnboardingIntegrityView(progress: progress(for: .integrity)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .howItWorks
                    }
                }
                .transition(stepTransition)
            case .howItWorks:
                OnboardingHowItWorksView(progress: progress(for: .howItWorks)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .jumuahReminder
                    }
                }
                .transition(stepTransition)
            case .jumuahReminder:
                OnboardingJumuahReminderView(progress: progress(for: .jumuahReminder)) { selection, timezone in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pendingStepDetails = PendingStepDetails(jumuahTime: selection, timezone: timezone)
                        step = .notificationsPrePrompt
                    }
                }
                .transition(stepTransition)
            case .notificationsPrePrompt:
                OnboardingNotificationsPrePromptView(progress: progress(for: .notificationsPrePrompt)) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .paywall
                    }
                }
                .transition(stepTransition)
            case .paywall:
                OnboardingPaywallView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(stepTransition)
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

struct OnboardingStepLayout<Background: View, Content: View, Footer: View>: View {
    let progress: OnboardingProgress
    let progressForeground: Color
    let progressBackground: Color
    let background: Background
    let content: Content
    let footer: Footer
    let contentSpacing: CGFloat

    init(
        progress: OnboardingProgress,
        progressForeground: Color,
        progressBackground: Color,
        contentSpacing: CGFloat = 22,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.progress = progress
        self.progressForeground = progressForeground
        self.progressBackground = progressBackground
        self.contentSpacing = contentSpacing
        self.background = background()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressIndicator(progress, background: progressBackground, foreground: progressForeground)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                Spacer(minLength: 10)

                VStack(spacing: contentSpacing) {
                    content
                }
                .padding(.horizontal, 28)

                Spacer()

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
    }
}

struct OnboardingReveal: ViewModifier {
    let index: Int
    let baseDelay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let shouldAnimate = !reduceMotion
        return content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: shouldAnimate ? (isVisible ? 0 : 12) : 0)
            .animation(
                shouldAnimate ? .easeOut(duration: 0.55).delay(baseDelay * Double(index)) : nil,
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    func onboardingReveal(_ index: Int, baseDelay: Double = 0.12) -> some View {
        modifier(OnboardingReveal(index: index, baseDelay: baseDelay))
    }
}

struct OnboardingTimedFade: ViewModifier {
    let delay: Double
    let duration: Double
    @Binding var revealAll: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let shouldAnimate = !reduceMotion
        return content
            .opacity((isVisible || revealAll || reduceMotion) ? 1 : 0)
            .animation(
                shouldAnimate && !revealAll ? .easeOut(duration: duration).delay(delay) : nil,
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    func onboardingTimedFade(
        delay: Double,
        revealAll: Binding<Bool>,
        duration: Double = 0.3
    ) -> some View {
        modifier(OnboardingTimedFade(delay: delay, duration: duration, revealAll: revealAll))
    }
}

enum OnboardingTypography {
    static let hero = Font.system(size: 32, weight: .semibold, design: .serif)
    static let title = Font.system(size: 30, weight: .bold, design: .serif)
    static let eyebrow = Font.system(size: 18, weight: .regular, design: .serif)
    static let subtitle = Font.system(size: 18, weight: .regular, design: .default)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
}

struct SplashWordmark: View {
    var height: CGFloat = 68
    
    var body: some View {
        Image("SplashWordmark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct OnboardingRememberView: View {
    let progress: OnboardingProgress
    var onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealAll = false
    @State private var isButtonEnabled = false

    private let fadeDuration: Double = 1.0
    private let buttonDelay: Double = 5.8
    
    var body: some View {
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.deepGreen.opacity(0.8),
            progressBackground: BrandPalette.cream,
            contentSpacing: 20,
            background: { BrandPalette.cream },
            content: {
                Text("Imagine if you could revisit it.")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.deepGreen)
                    .multilineTextAlignment(.center)
                    .onboardingTimedFade(delay: 0.4, revealAll: $revealAll, duration: fadeDuration)

                VStack(spacing: 18) {
                    Text("That powerful reminder.")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .onboardingTimedFade(delay: 1.4, revealAll: $revealAll, duration: fadeDuration)

                    Text("The exact words.")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .onboardingTimedFade(delay: 2.4, revealAll: $revealAll, duration: fadeDuration)

                    Text("Whenever you need them.")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .onboardingTimedFade(delay: 3.4, revealAll: $revealAll, duration: fadeDuration)
                }
                
                (
                    Text("Khutbah Notes")
                        .fontWeight(.semibold)
                    + Text(" makes it possible.")
                )
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundColor(BrandPalette.deepGreen.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.top, 28)
                .onboardingTimedFade(delay: 4.8, revealAll: $revealAll, duration: fadeDuration)
            },
            footer: {
                ZStack {
                    Button(action: handleGetStarted) {
                        Text("Continue")
                    }
                    .buttonStyle(SolidGreenButtonStyle())
                    .disabled(!isButtonEnabled)
                }
                .overlay {
                    if !isButtonEnabled {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                revealAllContent()
                            }
                    }
                }
                .onboardingTimedFade(delay: 5.8, revealAll: $revealAll, duration: fadeDuration)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                revealAllContent()
            }
        )
        .onAppear {
            startRevealTiming()
        }
    }
    
    private func handleGetStarted() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGetStarted()
    }

    private func startRevealTiming() {
        guard !reduceMotion else {
            revealAllContent()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonDelay + fadeDuration) {
            isButtonEnabled = true
        }
    }

    private func revealAllContent() {
        if !revealAll {
            revealAll = true
        }
        isButtonEnabled = true
    }
}

struct OnboardingWelcomeView: View {
    let progress: OnboardingProgress
    var onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealAll = false
    @State private var isButtonEnabled = false

    private let fadeDuration: Double = 1.0
    private let emphasizeFadeDuration: Double = 1.3
    private let buttonDelay: Double = 5.6
    
    var body: some View {
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.cream.opacity(0.75),
            progressBackground: .clear,
            contentSpacing: 20,
            background: { BrandBackground() },
            content: {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ")
                            .font(OnboardingTypography.hero)
                            .foregroundColor(BrandPalette.cream)
                            .multilineTextAlignment(.center)

                        Text("Assalamu alaikum")
                            .font(OnboardingTypography.eyebrow)
                            .foregroundColor(BrandPalette.cream.opacity(0.94))
                    }
                    .padding(.top, 36)

                    Spacer(minLength: 20)

                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Text("Ever hear an inspiring khutbah...")
                                .font(OnboardingTypography.title)
                                .foregroundColor(BrandPalette.cream)
                                .multilineTextAlignment(.center)
                                .onboardingTimedFade(delay: 1.0, revealAll: $revealAll, duration: fadeDuration)

                            Text("but forget the message by Monday")
                                .font(.system(size: 18, weight: .medium, design: .default))
                                .foregroundColor(BrandPalette.cream.opacity(0.95))
                                .multilineTextAlignment(.center)
                                .onboardingTimedFade(delay: 1.8, revealAll: $revealAll, duration: fadeDuration)
                        }

                        VStack(spacing: 0) {
                            Text("You're not alone.")
                                .font(.system(size: 20, weight: .semibold, design: .default))
                                .foregroundColor(BrandPalette.cream.opacity(0.95))
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 18)
                                .onboardingTimedFade(delay: 3.2, revealAll: $revealAll, duration: emphasizeFadeDuration)

                            Text("Most of us remember the feeling, but lose the words.")
                                .font(.system(size: 20, weight: .regular, design: .default))
                                .foregroundColor(BrandPalette.cream.opacity(0.88))
                                .multilineTextAlignment(.center)
                                .onboardingTimedFade(delay: 4.4, revealAll: $revealAll, duration: fadeDuration)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            footer: {
                ZStack {
                    Button(action: handleGetStarted) {
                        Text("That's Why We Built This")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonGreenTextStyle())
                    .disabled(!isButtonEnabled)
                }
                .overlay {
                    if !isButtonEnabled {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                revealAllContent()
                            }
                    }
                }
                .onboardingTimedFade(delay: 5.6, revealAll: $revealAll, duration: fadeDuration)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                revealAllContent()
            }
        )
        .onAppear {
            startRevealTiming()
        }
    }
    
    private func handleGetStarted() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGetStarted()
    }

    private func startRevealTiming() {
        guard !reduceMotion else {
            revealAllContent()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonDelay + fadeDuration) {
            isButtonEnabled = true
        }
    }

    private func revealAllContent() {
        if !revealAll {
            revealAll = true
        }
        isButtonEnabled = true
    }
}

struct OnboardingIntegrityView: View {
    let progress: OnboardingProgress
    var onContinue: () -> Void
    private let contentWidth: CGFloat = 320
    
    var body: some View {
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.cream.opacity(0.75),
            progressBackground: .clear,
            contentSpacing: 18,
            background: { BrandBackground() },
            content: {
                Text("Your Khutbah.\nNothing Added.")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.cream)
                    .padding(.bottom, 4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: contentWidth)
                    .onboardingReveal(0)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("Uses only YOUR recording")
                    bullet("No fatwas or rulings")
                    bullet("No invented Quran or hadith")
                    bullet("Private & secure")
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .onboardingReveal(1)

                Divider()
                    .background(BrandPalette.cream.opacity(0.35))
                    .padding(.vertical, 10)
                    .frame(maxWidth: contentWidth)
                    .onboardingReveal(2)

                Text("Our summaries never introduce Islamic content that was not said by the khateeb.")
                    .font(OnboardingTypography.subtitle)
                    .foregroundColor(BrandPalette.cream.opacity(0.9))
                    .padding(.top, 2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: contentWidth)
                    .onboardingReveal(3)
            },
            footer: {
                Button(action: handleContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CreamButtonGreenTextStyle())
                .onboardingReveal(4)
            }
        )
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
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.deepGreen.opacity(0.75),
            progressBackground: BrandPalette.cream,
            background: { BrandPalette.cream },
            content: {
                Text("How It Works")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.deepGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: contentWidth)
                    .onboardingReveal(0)

                VStack(alignment: .leading, spacing: 14) {
                    HowItWorksRow(
                        icon: "mic.circle.fill",
                        title: "Record the khutbah",
                        detail: "Discreetly capture the audio during Jumu'ah."
                    )
                    HowItWorksRow(
                        icon: "list.bullet.rectangle.portrait",
                        title: "Get key takeaways",
                        detail: "Transcriptions, summaries, ayahs, translations, and reminders"
                    )
                    HowItWorksRow(
                        icon: "arrow.clockwise.circle.fill",
                        title: "Reflect all week",
                        detail: "Stay connected to the message beyond Friday."
                    )
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .onboardingReveal(1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SUMMARY PREVIEW")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.55))
                        .tracking(1.2)
                    
                    summaryPreviewCard(
                        title: "Key Points",
                        bullets: [
                            "Sabr through trials strengthens faith and steadies the heart",
                            "Guarding the tongue protects relationships and preserves dignity",
                            "Consistency in small deeds builds lasting spiritual growth"
                        ]
                    )
                }
                .onboardingReveal(2)
            },
            footer: {
                Button(action: handleContinue) {
                    Text("Continue")
                }
                .buttonStyle(SolidGreenButtonStyle())
                .onboardingReveal(3)
            }
        )
    }
    
    private func summaryPreviewCard(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Theme.primaryGreen, Theme.secondaryGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(Theme.bodyFont)
                            .foregroundColor(.black)
                        Text(bullets[index])
                            .font(Theme.bodyFont)
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if index < bullets.count - 1 {
                        Rectangle()
                            .fill(Theme.mutedText.opacity(0.35))
                            .frame(height: 0.5)
                            .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.primaryGreen.opacity(0.08), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 8)
                .blur(radius: 8)
        )
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
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
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.cream.opacity(0.75),
            progressBackground: .clear,
            contentSpacing: 20,
            background: { BrandBackground() },
            content: {
                Text("When does your Jumu'ah start?")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.cream)
                    .multilineTextAlignment(.center)
                    .onboardingReveal(0)

                LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                    ForEach(times, id: \.self) { time in
                        Button(action: { selectedTime = time }) {
                            Text(time)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TimeChipStyle(isSelected: selectedTime == time))
                    }
                }
                .onboardingReveal(1)

                Text("We'll send you a reminder shortly before the khutbah begins.")
                    .font(OnboardingTypography.subtitle)
                    .foregroundColor(BrandPalette.cream.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .onboardingReveal(2)
            },
            footer: {
                Button(action: handleContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CreamButtonGreenTextStyle())
                .opacity(selectedTime == nil ? 0.6 : 1)
                .disabled(selectedTime == nil)
                .onboardingReveal(3)
            }
        )
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
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: LectureStore
    @AppStorage("notificationPrefChoice") private var storedNotificationChoice: String?
    @State private var isRequestingPermission = false
    @State private var revealAll = false
    
    private let contentWidth: CGFloat = 340
    private let fadeDuration: Double = 1.1
    private let baseFadeDelay: Double = 0.6
    private let stepFadeDelay: Double = 1.0
    private let extraPauseAfterNudge: Double = 0.6
    private let lastRevealIndex: Int = 7
    
    var body: some View {
        OnboardingStepLayout(
            progress: progress,
            progressForeground: BrandPalette.deepGreen.opacity(0.75),
            progressBackground: BrandPalette.cream,
            contentSpacing: 20,
            background: { BrandPalette.cream },
            content: {
                Text("Don’t Miss the Khutbah")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.deepGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: contentWidth)
                    .onboardingTimedFade(delay: fadeDelay(0), revealAll: $revealAll, duration: fadeDuration)

                VStack(spacing: 10) {
                    storyLine("Fridays can be hectic…", index: 1)
                    storyLine("Without a nudge, it’s easy to forget to record.", index: 2)
                    storyLine("Let us send a gentle reminder inshallah", index: 3)
                }
                .frame(maxWidth: contentWidth)

                notificationCard
                    .onboardingTimedFade(delay: fadeDelay(4), revealAll: $revealAll, duration: fadeDuration)
            },
            footer: {
                VStack(spacing: 10) {
                    Button(action: handleAllowTapped) {
                        Text("Yes, remind me before Jumu’ah")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SolidGreenButtonStyle())
                    .disabled(isRequestingPermission)

                    Text("No spam. Turn off anytime.")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(BrandPalette.deepGreen.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Button(action: handleNotNowTapped) {
                        Text("Maybe Later")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BrandPalette.deepGreen.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .disabled(isRequestingPermission)
                }
                .allowsHitTesting(revealAll)
                .onboardingTimedFade(delay: fadeDelay(5), revealAll: $revealAll, duration: fadeDuration)
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                revealAllContent()
            }
        )
        .onAppear {
            startRevealTiming()
        }
    }
    
    private func storyLine(_ text: String, index: Int) -> some View {
        Text(text)
            .font(OnboardingTypography.subtitle)
            .foregroundColor(BrandPalette.deepGreen.opacity(0.92))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .onboardingTimedFade(delay: fadeDelay(index), revealAll: $revealAll, duration: fadeDuration)
    }

    private func fadeDelay(_ index: Int) -> Double {
        baseFadeDelay + (Double(index) * stepFadeDelay) + (index >= 3 ? extraPauseAfterNudge : 0)
    }

    private func startRevealTiming() {
        guard !reduceMotion else {
            revealAllContent()
            return
        }
        let finalDelay = fadeDelay(lastRevealIndex) + fadeDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
            revealAllContent()
        }
    }

    private func revealAllContent() {
        if !revealAll {
            revealAll = true
        }
    }

    @ViewBuilder
    private var notificationCard: some View {
        if let image = UIImage(named: "jummahreminder") ?? UIImage(named: "jummahreminder.png") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: contentWidth + 40)
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
        OnboardingStepLayout(
            progress: OnboardingProgress(current: 6, total: 6),
            progressForeground: BrandPalette.cream.opacity(0.75),
            progressBackground: .clear,
            contentSpacing: 16,
            background: { BrandBackground() },
            content: {
                Text("Onboarding, continued")
                    .font(OnboardingTypography.title)
                    .foregroundColor(BrandPalette.cream)
                    .multilineTextAlignment(.center)
                    .onboardingReveal(0)

                Text("Swap this screen with your next onboarding step when it's ready.")
                    .font(OnboardingTypography.subtitle)
                    .foregroundColor(BrandPalette.cream.opacity(0.94))
                    .multilineTextAlignment(.center)
                    .onboardingReveal(1)
            },
            footer: {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SolidGreenButtonStyle())
                .onboardingReveal(2)
            }
        )
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
