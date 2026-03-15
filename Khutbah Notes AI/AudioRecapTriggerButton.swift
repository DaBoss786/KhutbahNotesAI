import SwiftUI

struct AudioRecapTriggerButton: View {
    let action: () -> Void
    var isDisabled: Bool = false
    var isLoading: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Audio Recap")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isDisabled ? Theme.mutedText : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isDisabled {
                        Capsule()
                            .fill(Color.white.opacity(0.65))
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isDisabled ? 0.5 : 0.2), lineWidth: 1)
            )
            .shadow(
                color: isDisabled ? .clear : Theme.shadow,
                radius: isDisabled ? 0 : 6,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel("Audio Recap")
    }
}
