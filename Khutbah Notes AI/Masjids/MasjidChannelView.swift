import SwiftUI

struct MasjidChannelView: View {
    @EnvironmentObject private var masjidStore: MasjidStore
    let masjid: Masjid

    private var khutbahs: [MasjidKhutbah] {
        masjidStore.khutbahs(for: masjid.id)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if khutbahs.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(khutbahs) { khutbah in
                            NavigationLink {
                                MasjidLectureView(masjid: masjid, khutbah: khutbah)
                            } label: {
                                khutbahRow(khutbah)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(masjid.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            masjidStore.observeKhutbahs(for: masjid.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(masjid.name)
                .font(Theme.largeTitleFont)
                .foregroundColor(.black)
            Text(locationText)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
        }
    }

    private var locationText: String {
        [masjid.city, masjid.state ?? "", masjid.country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No ready khutbahs yet")
                .font(Theme.titleFont)
                .foregroundColor(.black)
            Text("Khutbah summaries will appear here once processing is complete.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }

    private func khutbahRow(_ khutbah: MasjidKhutbah) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(khutbah.title)
                .font(Theme.titleFont)
                .foregroundColor(.black)

            HStack(spacing: 8) {
                if let dateText = dateText(for: khutbah.date ?? khutbah.createdAt) {
                    Label(dateText, systemImage: "calendar")
                }
                if let speaker = khutbah.speaker, !speaker.isEmpty {
                    Text("•")
                    Text(speaker)
                }
            }
            .font(.caption)
            .foregroundColor(Theme.mutedText)

            if let preview = previewText(for: khutbah), !preview.isEmpty {
                Text(preview)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }

    private func previewText(for khutbah: MasjidKhutbah) -> String? {
        if let mainTheme = khutbah.mainTheme?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mainTheme.isEmpty {
            return mainTheme
        }
        return nil
    }

    private func dateText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
