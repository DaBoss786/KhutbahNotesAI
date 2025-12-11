//
//  SplashView.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/5/25.
//

import SwiftUI

struct SplashView: View {
    @Binding var isActive: Bool
    @State private var logoScale: CGFloat = 0.94
    
    var body: some View {
        ZStack {
            background
            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .scaleEffect(logoScale)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
        .ignoresSafeArea()
        .onAppear(perform: animateIn)
    }
    
    private var background: some View {
        BrandBackground()
    }
    
    private func animateIn() {
        withAnimation(.easeOut(duration: 0.9)) {
            logoScale = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.easeIn(duration: 0.25)) {
                isActive = false
            }
        }
    }
}

#Preview {
    StatefulPreviewWrapper(true) { isActive in
        SplashView(isActive: isActive)
    }
}

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content
    
    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }
    
    var body: some View {
        content($value)
    }
}
