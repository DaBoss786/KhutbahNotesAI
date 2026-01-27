import SwiftUI

struct WidgetBannerView: View {
    var onTap: () -> Void = {}
    var onDismiss: () -> Void = {}
    @State private var didTapDismiss = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.primaryGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text("New: Daily Ayah Lock Screen widget")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.primaryGreen)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Shows a verse daily and becomes a Jummah recorder on Fridays.")
                    .font(.caption)
                    .foregroundColor(Theme.primaryGreen.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: handleDismissTapped) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.primaryGreen)
                    .frame(width: 22, height: 22)
                    .background(Theme.primaryGreen.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss widget banner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primaryGreen.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.primaryGreen.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !didTapDismiss else { return }
            onTap()
        }
    }

    private func handleDismissTapped() {
        didTapDismiss = true
        onDismiss()
        DispatchQueue.main.async {
            didTapDismiss = false
        }
    }
}

