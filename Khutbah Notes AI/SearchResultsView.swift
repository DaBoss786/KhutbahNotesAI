//
//  SearchResultsView.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var store: LectureStore
    let query: String
    @Binding var selectedTab: Int
    @Binding var dashboardNavigationDepth: Int

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Lecture] {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else { return [] }
        let normalizedQuery = normalized(trimmed)
        return store.lectures.filter { lecture in
            guard lecture.status == .ready, let summary = lecture.summary else { return false }
            let fields = [summary.mainTheme] + summary.keyPoints +
                summary.explicitAyatOrHadith + summary.weeklyActions
            return fields.contains { normalized($0).contains(normalizedQuery) }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Search Results")
                    .font(Theme.largeTitleFont)
                    .foregroundColor(.black)

                if trimmedQuery.isEmpty {
                    Text("Enter a search term on the dashboard to find summaries.")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.mutedText)
                } else {
                    Text("\"\(trimmedQuery)\"")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.mutedText)

                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.mutedText)

                    if results.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.primaryGreen)
                .frame(width: 36, height: 36)
                .background(Theme.primaryGreen.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text("No summaries matched your search.")
                    .font(Theme.titleFont)
                    .foregroundColor(.black)
                Text("Try a different keyword or phrase.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
        .padding(.top, 4)
    }

    private var resultsList: some View {
        VStack(spacing: 12) {
            ForEach(results) { lecture in
                NavigationLink {
                    NavigationDepthTracker(depth: $dashboardNavigationDepth) {
                        LectureDetailView(
                            lecture: lecture,
                            selectedRootTab: $selectedTab
                        )
                    }
                } label: {
                    LectureCardView(lecture: lecture)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
