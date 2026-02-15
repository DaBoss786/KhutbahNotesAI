import SwiftUI

struct MasjidDirectoryView: View {
    @EnvironmentObject private var masjidStore: MasjidStore
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMasjids: [Masjid] {
        let query = trimmedQuery.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        if query.isEmpty {
            return masjidStore.masjids
        }
        return masjidStore.masjids.filter { masjid in
            let candidates = [
                masjid.name,
                masjid.city,
                masjid.state ?? "",
                masjid.country,
            ]
            return candidates.contains { value in
                value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).contains(query)
            }
        }
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
            }
        }
        .onAppear {
            masjidStore.start()
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar
                if !masjidStore.hasLoadedMasjids {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else if filteredMasjids.isEmpty {
                    emptyState
                } else {
                    masjidList
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Masjids")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Masjid Channels")
                .font(Theme.largeTitleFont)
                .foregroundColor(.black)
            Text("Curated khutbah summaries from trusted masjids.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Want your masjid included here?")
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
                NavigationLink(
                    destination: StaticContentView(
                        title: "Masjid Partnerships",
                        bodyText: PlaceholderCopy.masjidPartnerships
                    )
                ) {
                    Text("Partner with us!")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Theme.primaryGreen)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.mutedText)
            TextField("Search masjids", text: $searchQuery)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    isSearchFocused = false
                }
            if !trimmedQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.mutedText.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            Button {
                isSearchFocused = false
            } label: {
                Text("Search")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.primaryGreen.opacity(0.12))
                    .foregroundColor(Theme.primaryGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trimmedQuery.isEmpty)
            .opacity(trimmedQuery.isEmpty ? 0.6 : 1)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if trimmedQuery.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.primaryGreen)
                    Text("No masjid channels yet")
                        .font(Theme.titleFont)
                        .foregroundColor(.black)
                }

                Text("Channels will appear here once they are added by the admin.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.primaryGreen)
                    Text("No matching masjids")
                        .font(Theme.titleFont)
                        .foregroundColor(.black)
                }

                Text("Try a different search term.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }

    private var masjidList: some View {
        VStack(spacing: 12) {
            ForEach(filteredMasjids) { masjid in
                NavigationLink {
                    MasjidChannelView(masjid: masjid)
                } label: {
                    masjidRow(masjid)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func masjidRow(_ masjid: Masjid) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(masjid.name)
                .font(Theme.titleFont)
                .foregroundColor(.black)
            Text(locationText(for: masjid))
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
            if let lastUpdated = lastUpdatedText(for: masjid.lastUpdatedAt) {
                Text(lastUpdated)
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }

    private func locationText(for masjid: Masjid) -> String {
        let parts = [masjid.city, masjid.state ?? "", masjid.country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location unavailable" : parts.joined(separator: ", ")
    }

    private func lastUpdatedText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Updated \(formatter.string(from: date))"
    }
}
