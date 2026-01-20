//
//  OnboardingProgress.swift
//  Khutbah Notes AI
//
//  Small progress indicator for multi-step onboarding.
//

import SwiftUI

struct OnboardingProgress: Equatable {
    let current: Int
    let total: Int
}

struct OnboardingProgressView: View {
    let progress: OnboardingProgress
    let foreground: Color
    let background: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(1...progress.total, id: \.self) { index in
                    Capsule()
                        .fill(index <= progress.current ? foreground : foreground.opacity(0.25))
                        .frame(width: 28, height: 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background.opacity(background == .clear ? 0 : 0.26))
            )
            
            Text("Step \(progress.current) of \(progress.total)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(foreground.opacity(0.75))
        }
    }
}

@ViewBuilder
func progressIndicator(_ progress: OnboardingProgress, background: Color, foreground: Color) -> some View {
    OnboardingProgressView(progress: progress, foreground: foreground, background: background)
}
