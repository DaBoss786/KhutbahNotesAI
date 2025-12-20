//
//  DeleteAccountView.swift
//  Khutbah Notes AI
//

import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var store: LectureStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var showConfirmDialog = false
    @State private var isDeleting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSuccessToast = false

    private let requiredPhrase = "DELETE"

    private var canDelete: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == requiredPhrase
            && !isDeleting
    }

    var body: some View {
        Form {
            Section {
                Text("Deleting your account permanently removes your recordings, transcripts, summaries, and settings. This can't be undone.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Type DELETE to confirm")) {
                TextField("DELETE", text: $confirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    showConfirmDialog = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Text("Delete Account")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundColor(.red)
                .disabled(!canDelete)
            }
        }
        .navigationTitle("Delete Account")
        .confirmationDialog("Delete account?", isPresented: $showConfirmDialog, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await handleDelete() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and data.")
        }
        .alert("Couldn't delete account", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay(alignment: .top) {
            if showSuccessToast {
                Text("Account deleted")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Theme.primaryGreen.opacity(0.95))
                            .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 8, x: 0, y: 6)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
    }

    private func handleDelete() async {
        guard canDelete else { return }
        isDeleting = true

        do {
            try await store.deleteAccount()
            await MainActor.run {
                isDeleting = false
                withAnimation {
                    showSuccessToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                isDeleting = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
