//
//  RamadanGiftModalView.swift
//  Khutbah Notes AI
//

import SwiftUI

struct RamadanGiftModalView: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AnimatedGiftBoxView()
                    .padding(.top, 6)

                Text("Ramadan Gift!")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundColor(BrandPalette.deepGreen)
                    .multilineTextAlignment(.center)

                Text("Enjoy 60 minutes of free recording and full access to transcripts, summaries, and translations.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(BrandPalette.deepGreen.opacity(0.85))
                    .multilineTextAlignment(.center)

                Button(action: handleDismiss) {
                    Text("Get Started!")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SolidGreenButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(BrandPalette.cream)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
    }

    private func handleDismiss() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onDismiss()
    }
}

struct AnimatedGiftBoxView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandPalette.gradientTop.opacity(0.18))
                .frame(width: 170, height: 170)

            Circle()
                .fill(BrandPalette.gradientBottom.opacity(0.18))
                .frame(width: 135, height: 135)

            sparkles

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BrandPalette.deepGreen, BrandPalette.gradientBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(BrandPalette.cream.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: "gift.fill")
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundColor(BrandPalette.cream)
            }
            .scaleEffect(isAnimating ? 1.0 : 0.96)
            .rotationEffect(.degrees(isAnimating ? 0 : -4))
            .offset(y: isAnimating ? -2 : 2)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isAnimating
            )
        }
        .frame(width: 180, height: 180)
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
            sparkle = true
        }
    }

    private var sparkles: some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(BrandPalette.cream.opacity(0.95))
                .offset(x: -52, y: -56)
                .scaleEffect(sparkle ? 1.0 : 0.75)
                .opacity(sparkle ? 1.0 : 0.4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: sparkle
                )

            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BrandPalette.cream.opacity(0.8))
                .offset(x: 56, y: -50)
                .scaleEffect(sparkle ? 0.85 : 1.1)
                .opacity(sparkle ? 0.9 : 0.35)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.2),
                    value: sparkle
                )
        }
    }
}

#Preview {
    RamadanGiftModalView(onDismiss: {})
        .background(BrandBackground())
}
