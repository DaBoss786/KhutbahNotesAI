//
//  FeedbackView.swift
//  Khutbah Notes AI
//

import SwiftUI

struct FeedbackView: View {
    @EnvironmentObject private var store: LectureStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccessToast = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty && !trimmedMessage.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Email")) {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Message")) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $message)
                            .frame(minHeight: 140)

                        if trimmedMessage.isEmpty {
                            Text("Tell us what you think...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
                }
            }
            .navigationTitle("Feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { submitFeedback() }
                        .disabled(!canSubmit)
                }
            }
            .overlay(alignment: .top) {
                if showSuccessToast {
                    feedbackToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 12)
                }
            }
            .alert("Couldn't send feedback", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var feedbackToast: some View {
        Text("Thanks for the feedback")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Theme.primaryGreen.opacity(0.95))
                    .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 8, x: 0, y: 6)
            )
    }

    private func submitFeedback() {
        guard canSubmit else { return }
        isSubmitting = true

        Task {
            do {
                try await store.submitFeedback(email: trimmedEmail, message: trimmedMessage)
                await MainActor.run {
                    isSubmitting = false
                    withAnimation {
                        showSuccessToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
