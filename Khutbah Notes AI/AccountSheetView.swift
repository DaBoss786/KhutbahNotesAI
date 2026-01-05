import SwiftUI
import UIKit

struct AccountSheetView: View {
    @EnvironmentObject private var store: LectureStore
    let onClose: () -> Void
    let onUpgrade: () -> Void

    private var isPremiumPlan: Bool {
        (store.userUsage?.plan ?? "free") == "premium"
    }

    private var planName: String {
        isPremiumPlan ? "Premium" : "Free"
    }

    private var monthlyMinutesRemaining: Int {
        max(0, store.userUsage?.minutesRemaining ?? 0)
    }

    private var freeLifetimeMinutesRemaining: Int {
        if let remaining = store.userUsage?.freeLifetimeMinutesRemaining {
            return max(0, remaining)
        }
        let used = store.userUsage?.freeLifetimeMinutesUsed ?? 0
        return max(0, 60 - used)
    }

    private var userIdText: String {
        store.userId ?? "Not available"
    }

    private var canCopyUserId: Bool {
        store.userId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Account")
                    .font(.title2.bold())
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.mutedText)
                        .padding(8)
                        .background(Theme.cardBackground)
                        .clipShape(Circle())
                        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close account sheet")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Current plan")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                HStack(alignment: .center, spacing: 12) {
                    Text(planName)
                        .font(.title2.bold())
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: isPremiumPlan ? "crown.fill" : "leaf.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.primaryGreen)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 10) {
                Text(isPremiumPlan ? "Monthly minutes remaining" : "Lifetime minutes remaining")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                Text("\(isPremiumPlan ? monthlyMinutesRemaining : freeLifetimeMinutesRemaining) min")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryGreen)
                if !isPremiumPlan {
                    Text("Free plan includes 60 lifetime minutes.")
                        .font(.footnote)
                        .foregroundColor(Theme.mutedText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            if !isPremiumPlan {
                Button {
                    onUpgrade()
                } label: {
                    Text("Upgrade")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.primaryGreen)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 8, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("UID")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                HStack(alignment: .top, spacing: 12) {
                    Text(userIdText)
                        .font(.footnote)
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        if let userId = store.userId {
                            UIPasteboard.general.string = userId
                        }
                    } label: {
                        Text("Copy")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.primaryGreen.opacity(0.12))
                            .foregroundColor(Theme.primaryGreen)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCopyUserId)
                    .opacity(canCopyUserId ? 1 : 0.5)
                    .accessibilityLabel("Copy UID")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            Spacer()
        }
        .padding(24)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
