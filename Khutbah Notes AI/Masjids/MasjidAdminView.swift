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
    @State private var useQueueDateOverride = false
    @State private var queueDate = Date()
    @State private var manualTranscript = ""

    @State private var promoteMasjidId = ""
    @State private var sourceUserId = ""
    @State private var sourceLectureId = ""
    @State private var promoteTitle = ""
    @State private var promoteSpeaker = ""
    @State private var promoteTranscript = ""
    @State private var includePromotionAudio = true
    @State private var usePromoteDateOverride = false
    @State private var promoteDate = Date()

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

    private var canPromoteLecture: Bool {
        !promoteMasjidId.isEmpty &&
            !sourceUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !sourceLectureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
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
            setDefaultPromoteMasjid()
        }
        .onChange(of: masjidStore.masjids.count) { _ in
            setDefaultQueueMasjid()
            setDefaultPromoteMasjid()
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
                Toggle("Override Date", isOn: $useQueueDateOverride)
                if useQueueDateOverride {
                    DatePicker(
                        "Date",
                        selection: $queueDate,
                        displayedComponents: [.date]
                    )
                }

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

            Section("Promote Existing Lecture") {
                Picker("Masjid", selection: $promoteMasjidId) {
                    Text("Select").tag("")
                    ForEach(masjidStore.masjids) { masjid in
                        Text(masjid.name).tag(masjid.id)
                    }
                }

                TextField("Source User UID", text: $sourceUserId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Source Lecture ID", text: $sourceLectureId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Title override (optional)", text: $promoteTitle)
                TextField("Speaker override (optional)", text: $promoteSpeaker)

                Toggle("Override Date", isOn: $usePromoteDateOverride)
                if usePromoteDateOverride {
                    DatePicker(
                        "Date",
                        selection: $promoteDate,
                        displayedComponents: [.date]
                    )
                }

                Toggle("Copy source audio to masjid channel", isOn: $includePromotionAudio)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript override (optional)")
                        .font(.footnote)
                        .foregroundColor(Theme.mutedText)

                    ZStack(alignment: .topLeading) {
                        if promoteTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Leave empty to reuse source lecture transcript.")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.mutedText.opacity(0.8))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }

                        TextEditor(text: $promoteTranscript)
                            .frame(minHeight: 110)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                    }
                }

                Button {
                    Task { await promoteLecture() }
                } label: {
                    Text(isSubmitting ? "Promoting..." : "Promote to Masjid")
                }
                .disabled(!canPromoteLecture)
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

    private func setDefaultPromoteMasjid() {
        if promoteMasjidId.isEmpty {
            promoteMasjidId = masjidStore.masjids.first?.id ?? ""
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
                date: useQueueDateOverride ? queueDate : nil,
                manualTranscript: manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "Khutbah queued for processing."
            youtubeUrl = ""
            khutbahTitle = ""
            speaker = ""
            useQueueDateOverride = false
            queueDate = Date()
            manualTranscript = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func promoteLecture() async {
        guard canPromoteLecture else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await MasjidAdminAPI.promoteLecture(
                masjidId: promoteMasjidId,
                sourceUserId: sourceUserId.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceLectureId: sourceLectureId.trimmingCharacters(in: .whitespacesAndNewlines),
                title: promoteTitle,
                speaker: promoteSpeaker,
                date: usePromoteDateOverride ? promoteDate : nil,
                transcript: promoteTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
                includeAudio: includePromotionAudio
            )
            statusMessage = "Lecture promoted to masjid channel."
            sourceUserId = ""
            sourceLectureId = ""
            promoteTitle = ""
            promoteSpeaker = ""
            promoteTranscript = ""
            usePromoteDateOverride = false
            promoteDate = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
