import SwiftUI
import UIKit

struct QuranView: View {
    @StateObject private var viewModel = QuranViewModel()
    @EnvironmentObject private var quranNavigator: QuranNavigationCoordinator
    @State private var showSurahPicker = false
    @State private var selectedTextSize: TextSizeOption = .medium
    @State private var highlightedVerseId: String? = nil
    @State private var pendingScrollTarget: QuranCitationTarget? = nil

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showSurahPicker) {
            SurahPickerSheet(
                surahs: viewModel.surahs,
                selectedSurahId: viewModel.selectedSurah?.id,
                onSelect: { surah in
                    viewModel.selectSurah(surah)
                }
            )
        }
        .onChange(of: viewModel.translationOption) { _ in
            viewModel.reloadVerses()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                translationMenu
                Spacer()
                TextSizeToggle(selection: $selectedTextSize, showsBackground: true)
            }
            surahButton
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var translationMenu: some View {
        Menu {
            ForEach(QuranTranslationOption.allCases) { option in
                Button(option.rawValue) {
                    viewModel.translationOption = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.translationOption.rawValue)
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
            .foregroundColor(Theme.primaryGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.primaryGreen.opacity(0.12))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Translation")
    }

    private var surahButton: some View {
        Button {
            showSurahPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedSurah?.name ?? "Surah")
                    .font(Theme.titleFont)
                    .foregroundColor(.black)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
            .clipShape(Capsule())
            .shadow(color: Theme.shadow, radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select surah")
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.loadError {
            VStack(spacing: 12) {
                Text("Unable to load Quran data")
                    .font(.headline)
                    .foregroundColor(.black)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(Theme.mutedText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if viewModel.isLoading && viewModel.verses.isEmpty {
            ProgressView("Loading Quran")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(viewModel.verses) { verse in
                            QuranVerseRow(
                                verse: verse,
                                showsTranslation: viewModel.translationOption != .off,
                                textSize: selectedTextSize,
                                isHighlighted: verse.id == highlightedVerseId
                            )
                            .id(verse.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    handleNavigationTarget(quranNavigator.pendingTarget, proxy: proxy)
                }
                .onChange(of: quranNavigator.pendingTarget) { target in
                    handleNavigationTarget(target, proxy: proxy)
                }
                .onChange(of: viewModel.surahs) { _ in
                    if pendingScrollTarget != nil || quranNavigator.pendingTarget != nil {
                        handleNavigationTarget(
                            pendingScrollTarget ?? quranNavigator.pendingTarget,
                            proxy: proxy
                        )
                    }
                }
                .onChange(of: viewModel.verses) { _ in
                    scrollToPendingTarget(using: proxy)
                }
            }
        }
    }

    private func handleNavigationTarget(
        _ target: QuranCitationTarget?,
        proxy: ScrollViewProxy
    ) {
        guard let target else { return }
        pendingScrollTarget = target

        guard !viewModel.surahs.isEmpty else { return }
        if viewModel.selectedSurah?.id != target.surahId {
            guard viewModel.selectSurah(id: target.surahId) else {
                pendingScrollTarget = nil
                quranNavigator.clearPendingTarget()
                return
            }
            return
        }

        scrollToPendingTarget(using: proxy)
    }

    private func scrollToPendingTarget(using proxy: ScrollViewProxy) {
        guard let target = pendingScrollTarget else { return }
        guard !viewModel.isLoading else { return }
        guard viewModel.selectedSurah?.id == target.surahId else { return }

        let verseId = target.verseId
        guard viewModel.verses.contains(where: { $0.id == verseId }) else {
            pendingScrollTarget = nil
            quranNavigator.clearPendingTarget()
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(verseId, anchor: .center)
            }
        }
        highlightVerse(verseId)
        pendingScrollTarget = nil
        quranNavigator.clearPendingTarget()
    }

    private func highlightVerse(_ verseId: String) {
        highlightedVerseId = verseId
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if highlightedVerseId == verseId {
                highlightedVerseId = nil
            }
        }
    }
}

private struct QuranVerseRow: View {
    let verse: QuranVerse
    let showsTranslation: Bool
    let textSize: TextSizeOption
    let isHighlighted: Bool

    private var arabicFontSize: CGFloat {
        switch textSize {
        case .small:
            return 22
        case .medium:
            return 24
        case .large:
            return 26
        case .extraLarge:
            return 28
        }
    }

    private var arabicLineSpacing: CGFloat {
        switch textSize {
        case .small:
            return 4
        case .medium:
            return 6
        case .large:
            return 7
        case .extraLarge:
            return 8
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(verse.ayahNumber)")
                .font(.caption.bold())
                .foregroundColor(Theme.primaryGreen)
                .frame(width: 28, height: 28)
                .background(Theme.primaryGreen.opacity(0.12))
                .clipShape(Circle())
                .padding(.top, 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text(verse.arabicText)
                    .font(.custom("Geeza Pro", size: arabicFontSize))
                    .lineSpacing(arabicLineSpacing)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if showsTranslation, let translation = verse.translationText {
                    Text(translation)
                        .font(.system(size: textSize.bodySize, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.mutedText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.secondaryGreen.opacity(isHighlighted ? 0.12 : 0))
                .animation(
                    .easeInOut(duration: 0.5).repeatCount(1, autoreverses: true),
                    value: isHighlighted
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.secondaryGreen.opacity(isHighlighted ? 0.9 : 0), lineWidth: 2)
                .scaleEffect(isHighlighted ? 1.01 : 1)
                .animation(
                    .easeInOut(duration: 0.5).repeatCount(1, autoreverses: true),
                    value: isHighlighted
                )
        )
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)
    }
}

private struct SurahPickerSheet: View {
    let surahs: [Surah]
    let selectedSurahId: Int?
    let onSelect: (Surah) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    surahList
                        .navigationTitle("Select Surah")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    dismiss()
                                }
                                .foregroundColor(Theme.primaryGreen)
                            }
                        }
                }
            } else {
                NavigationView {
                    surahList
                        .navigationBarTitle("Select Surah", displayMode: .inline)
                        .navigationBarItems(trailing: Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(Theme.primaryGreen))
                }
            }
        }
    }

    private var filteredSurahs: [Surah] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return surahs }
        return surahs.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var surahList: some View {
        Group {
            if #available(iOS 15.0, *) {
                listView
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search surahs"
                    )
            } else {
                VStack(spacing: 12) {
                    fallbackSearchField
                        .padding(.horizontal)
                        .padding(.top, 8)
                    listView
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
            }
        }
    }

    private var listView: some View {
        List(filteredSurahs) { surah in
            Button {
                onSelect(surah)
                dismiss()
            } label: {
                HStack {
                    Text("\(surah.id)")
                        .font(.subheadline.bold())
                        .foregroundColor(Theme.primaryGreen)
                        .frame(width: 30, alignment: .leading)
                    Text(surah.name)
                        .foregroundColor(.black)
                    Spacer()
                    if surah.id == selectedSurahId {
                        Image(systemName: "checkmark")
                            .foregroundColor(Theme.primaryGreen)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var fallbackSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.mutedText)
            TextField("Search surahs", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .submitLabel(.done)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.mutedText.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 4)
        .accessibilityLabel("Search surahs")
    }

    private func dismissKeyboard() {
        isSearchFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
