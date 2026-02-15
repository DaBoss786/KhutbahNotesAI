import SwiftUI

struct MasjidAdminView: View {
    @EnvironmentObject private var masjidStore: MasjidStore

    @State private var selectedMasjidId: String = ""
    @State private var name = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = ""
    @State private var imageUrl = ""

    @State private var queueMasjidId = ""
    @State private var youtubeUrl = ""
    @State private var khutbahTitle = ""
    @State private var speaker = ""
    @State private var manualTranscript = ""

    @State private var statusMessage: String?
    @State private var isSubmitting = false

    private var canSaveMasjid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSubmitting
    }

    private var canQueueKhutbah: Bool {
        !queueMasjidId.isEmpty &&
            !youtubeUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSubmitting
    }

    var body: some View {
        Group {
            if masjidStore.isAdmin {
                formView
            } else if masjidStore.hasCheckedAdminStatus {
                deniedView
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Masjid Admin")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            masjidStore.start()
            Task {
                await masjidStore.refreshAdminStatus()
            }
            setDefaultQueueMasjid()
        }
    }

    private var formView: some View {
        Group {
            if #available(iOS 16.0, *) {
                baseForm
                    .scrollContentBackground(.hidden)
            } else {
                baseForm
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var baseForm: some View {
        Form {
            Section("Create / Edit Masjid") {
                Picker("Existing Masjid", selection: $selectedMasjidId) {
                    Text("Create New").tag("")
                    ForEach(masjidStore.masjids) { masjid in
                        Text(masjid.name).tag(masjid.id)
                    }
                }
                .onChange(of: selectedMasjidId) { _ in
                    loadSelectedMasjid()
                }

                TextField("Name", text: $name)
                TextField("City", text: $city)
                TextField("State (optional)", text: $state)
                TextField("Country", text: $country)
                TextField("Image URL (optional)", text: $imageUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await upsertMasjid() }
                } label: {
                    Text(isSubmitting ? "Saving..." : "Save Masjid")
                }
                .disabled(!canSaveMasjid)
            }

            Section("Queue YouTube Khutbah") {
                Picker("Masjid", selection: $queueMasjidId) {
                    Text("Select").tag("")
                    ForEach(masjidStore.masjids) { masjid in
                        Text(masjid.name).tag(masjid.id)
                    }
                }

                TextField("YouTube URL", text: $youtubeUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("Title (optional)", text: $khutbahTitle)
                TextField("Speaker (optional)", text: $speaker)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript (optional)")
                        .font(.footnote)
                        .foregroundColor(Theme.mutedText)

                    ZStack(alignment: .topLeading) {
                        if manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Paste transcript here to skip YouTube caption fetching.")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.mutedText.opacity(0.8))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }

                        TextEditor(text: $manualTranscript)
                            .frame(minHeight: 140)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                    }
                }

                Button {
                    Task { await queueKhutbah() }
                } label: {
                    Text(isSubmitting ? "Queueing..." : "Queue Khutbah")
                }
                .disabled(!canQueueKhutbah)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Section("Status") {
                    Text(statusMessage)
                        .font(.footnote)
                }
            }
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Admin access required")
                .font(Theme.titleFont)
                .foregroundColor(.black)
            Text("This screen is only available for approved admin UIDs.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func loadSelectedMasjid() {
        guard let masjid = masjidStore.masjids.first(where: { $0.id == selectedMasjidId }) else {
            name = ""
            city = ""
            state = ""
            country = ""
            imageUrl = ""
            return
        }
        name = masjid.name
        city = masjid.city
        state = masjid.state ?? ""
        country = masjid.country
        imageUrl = masjid.imageUrl ?? ""
    }

    private func setDefaultQueueMasjid() {
        if queueMasjidId.isEmpty {
            queueMasjidId = masjidStore.masjids.first?.id ?? ""
        }
    }

    private func upsertMasjid() async {
        guard canSaveMasjid else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await MasjidAdminAPI.upsertMasjid(
                masjidId: selectedMasjidId.isEmpty ? nil : selectedMasjidId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                state: state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                    nil :
                    state.trimmingCharacters(in: .whitespacesAndNewlines),
                country: country.trimmingCharacters(in: .whitespacesAndNewlines),
                imageUrl: imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                    nil :
                    imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "Masjid saved."
            selectedMasjidId = ""
            loadSelectedMasjid()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func queueKhutbah() async {
        guard canQueueKhutbah else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await MasjidAdminAPI.queueKhutbah(
                masjidId: queueMasjidId,
                youtubeUrl: youtubeUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                title: khutbahTitle,
                speaker: speaker,
                manualTranscript: manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "Khutbah queued for processing."
            youtubeUrl = ""
            khutbahTitle = ""
            speaker = ""
            manualTranscript = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
