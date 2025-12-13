//
//  Branding.swift
//  Khutbah Notes AI
//
//  Defines shared brand colors and reusable backgrounds.
//

import SwiftUI

enum BrandPalette {
    static let gradientTop = Color(red: 0.13, green: 0.61, blue: 0.39)    // #219B63
    static let gradientBottom = Color(red: 0.06, green: 0.48, blue: 0.33) // #0F7A54
    static let gradientOverlay = Color(red: 0.07, green: 0.53, blue: 0.36).opacity(0.25)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.94)          // #FAF8F0
    static let deepGreen = Color(red: 0.07, green: 0.36, blue: 0.25)      // #125C40-ish
    static let mutedCream = Color.white.opacity(0.6)
    
    static let primaryButtonTop = Color(red: 0.16, green: 0.63, blue: 0.40)
    static let primaryButtonBottom = Color(red: 0.12, green: 0.52, blue: 0.35)
}

struct BrandBackground: View {
    var body: some View {
        LinearGradient(
            colors: [BrandPalette.gradientTop, BrandPalette.gradientBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [BrandPalette.gradientOverlay, .clear],
                center: .center,
                startRadius: 10,
                endRadius: 480
            )
        )
    }
}
