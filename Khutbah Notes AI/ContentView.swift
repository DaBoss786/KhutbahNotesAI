//
//  ContentView.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import SwiftUI
import Combine
import AVFoundation
import FirebaseStorage
import UIKit

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environmentObject(LectureStore(seedMockData: true))
}

struct Theme {
    static let primaryGreen = Color(red: 0.12, green: 0.52, blue: 0.35)
    static let secondaryGreen = Color(red: 0.16, green: 0.63, blue: 0.40)
    static let background = Color(red: 0.95, green: 0.98, blue: 0.95)
    static let cardBackground = Color.white
    static let mutedText = Color(red: 0.43, green: 0.49, blue: 0.46)
    static let shadow = Color.black.opacity(0.08)
    
    static let largeTitleFont = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titleFont = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .rounded)
}

enum TextSizeOption: CaseIterable {
    case small
    case medium
    case large
    case extraLarge
    
    var bodySize: CGFloat {
        switch self {
        case .small:
            return 14
        case .medium:
            return 15
        case .large:
            return 16
        case .extraLarge:
            return 18
        }
    }
    
    var headingSize: CGFloat {
        switch self {
        case .small:
            return 16
        case .medium:
            return 17
        case .large:
            return 18
        case .extraLarge:
            return 20
        }
    }
    
    var label: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        case .extraLarge:
            return "Extra Large"
        }
    }
    
    var next: TextSizeOption {
        switch self {
        case .small:
            return .medium
        case .medium:
            return .large
        case .large:
            return .extraLarge
        case .extraLarge:
            return .small
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var toastMessage: String? = nil
    @State private var toastActionTitle: String? = nil
    @State private var toastAction: (() -> Void)? = nil
    @State private var showPaywall = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NotesView()
                    .tabItem {
                        Image(systemName: "book.closed.fill")
                        Text("Notes")
                    }
                    .tag(0)
                
                RecordLectureView(
                    selectedTab: $selectedTab,
                    onShowToast: { message, actionTitle, action in
                        withAnimation {
                            toastMessage = message
                            toastActionTitle = actionTitle
                            toastAction = action
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation {
                                toastMessage = nil
                                toastActionTitle = nil
                                toastAction = nil
                            }
                        }
                    },
                    onShowPaywall: {
                        showPaywall = true
                    }
                )
                .tabItem {
                    Label("Record", systemImage: "plus")
                        .opacity(0) // Hidden; replaced by floating button
                }
                .tag(1)
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(2)
            }
            .tint(Theme.primaryGreen)
            .sheet(isPresented: $showPaywall) {
                OnboardingPaywallView {
                    showPaywall = false
                }
            }
            
            Button(action: { selectedTab = 1 }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 68, height: 68)
                .shadow(color: Theme.primaryGreen.opacity(0.28), radius: 12, x: 0, y: 10)
            }
            .offset(y: -10)
            
            if let message = toastMessage {
                let actionTitle = toastActionTitle ?? "OK"
                ToastView(message: message, actionTitle: actionTitle) {
                    toastAction?()
                    withAnimation {
                        toastMessage = nil
                        toastActionTitle = nil
                        toastAction = nil
                    }
                }
                .padding(.bottom, 90)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var store: LectureStore
    @State private var selectedSegment = 0
    @State private var showRenameSheet = false
    @State private var showMoveSheet = false
    @State private var showCreateFolderSheet = false
    @State private var showDeleteAlert = false
    @State private var selectedLecture: Lecture?
    @State private var renameText = ""
    @State private var moveSelection: String?
    @State private var newFolderName = ""
    @State private var inlineFolderName = ""
    @State private var isCreatingInlineFolder = false
    @State private var pendingDeleteLecture: Lecture?
    @State private var showAddToFolderSheet = false
    @State private var addToFolderTarget: Folder?
    @State private var addToFolderSelections: Set<String> = []
    @State private var showPaywall = false
    
    private let segments = ["All Notes", "Folders"]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }
    
    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    content
                }
                .navigationBarHidden(true)
            } else {
                NavigationView {
                    content
                }
                .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: $showRenameSheet, onDismiss: { renameText = "" }) {
            renameSheet
        }
        .sheet(isPresented: $showMoveSheet, onDismiss: {
            moveSelection = nil
            isCreatingInlineFolder = false
            inlineFolderName = ""
        }) {
            moveSheet
        }
        .sheet(isPresented: $showCreateFolderSheet, onDismiss: { newFolderName = "" }) {
            createFolderSheet
        }
        .sheet(isPresented: $showAddToFolderSheet, onDismiss: {
            addToFolderSelections = []
            addToFolderTarget = nil
        }) {
            addToFolderSheet
        }
        .sheet(isPresented: $showPaywall) {
            OnboardingPaywallView {
                showPaywall = false
            }
        }
        .alert("Delete lecture?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let lecture = pendingDeleteLecture {
                    store.deleteLecture(lecture)
                }
                pendingDeleteLecture = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLecture = nil
            }
        } message: {
            Text("This will delete the lecture and its audio file.")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                if (store.userUsage?.plan ?? "free") != "premium" {
                    PromoBannerView {
                        showPaywall = true
                    }
                }
                segmentPicker
                if selectedSegment == 0 {
                    lectureList
                } else {
                    foldersList
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .background(Theme.background.ignoresSafeArea())
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formattedDate)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Theme.mutedText)
            HStack(alignment: .center) {
                Text("Khutbah Notes")
                    .font(Theme.largeTitleFont)
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.primaryGreen)
            }
            Text("As-salamu alaikum")
                .font(.subheadline)
                .foregroundColor(Theme.mutedText)
        }
    }
    
    private var segmentPicker: some View {
        Picker("Filter", selection: $selectedSegment) {
            ForEach(0..<segments.count, id: \.self) { index in
                Text(segments[index])
                    .tag(index)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var lectureList: some View {
        VStack(spacing: 12) {
            ForEach(store.lectures) { lecture in
                ZStack(alignment: .topTrailing) {
                    NavigationLink {
                        LectureDetailView(lecture: lecture)
                    } label: {
                        LectureCardView(lecture: lecture)
                    }
                    .buttonStyle(.plain)
                    
                    Menu {
                        Button("Rename") { startRename(for: lecture) }
                        Button("Move to Folder") { startMove(for: lecture) }
                        Button(role: .destructive) {
                            pendingDeleteLecture = lecture
                            showDeleteAlert = true
                        } label: {
                            Text("Delete")
                        }
                        Button("Cancel", role: .cancel) { }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.mutedText)
                            .padding(10)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Circle())
                            .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                }
            }
        }
    }
    
    private var foldersList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { showCreateFolderSheet = true }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Create a Folder")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.primaryGreen.opacity(0.12))
                .foregroundColor(Theme.primaryGreen)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            if !store.folders.isEmpty {
                VStack(spacing: 12) {
                    ForEach(store.folders) { folder in
                        NavigationLink {
                            FolderDetailView(
                                folder: folder,
                                lectures: lectures(in: folder),
                                onRename: { lecture in startRename(for: lecture) },
                                onMove: { lecture in startMove(for: lecture) },
                                onDelete: { lecture in
                                    pendingDeleteLecture = lecture
                                    showDeleteAlert = true
                                },
                                onAddLecture: {
                                    addToFolderTarget = folder
                                    showAddToFolderSheet = true
                                }
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(folder.name)
                                        .font(Theme.titleFont)
                                        .foregroundColor(.black)
                                    Text("\(lectureCount(for: folder)) lectures")
                                        .font(Theme.bodyFont)
                                        .foregroundColor(Theme.mutedText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.mutedText)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .cornerRadius(14)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func startRename(for lecture: Lecture) {
        selectedLecture = lecture
        renameText = lecture.title
        showRenameSheet = true
    }
    
    private func startMove(for lecture: Lecture) {
        selectedLecture = lecture
        moveSelection = lecture.folderId
        isCreatingInlineFolder = false
        inlineFolderName = ""
        showMoveSheet = true
    }
    
    private func lectureCount(for folder: Folder) -> Int {
        store.lectures.filter { $0.folderId == folder.id }.count
    }
    
    private func lectures(in folder: Folder) -> [Lecture] {
        store.lectures.filter { $0.folderId == folder.id }
    }
    
    private var addToFolderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to \(addToFolderTarget?.name ?? "folder")")
                .font(.title2.bold())
            
            if store.lectures.isEmpty {
                Text("No lectures available.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.lectures) { lecture in
                            Button(action: {
                                if addToFolderSelections.contains(lecture.id) {
                                    addToFolderSelections.remove(lecture.id)
                                } else {
                                    addToFolderSelections.insert(lecture.id)
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(lecture.title)
                                            .font(Theme.titleFont)
                                            .foregroundColor(.black)
                                        Text(lecture.date, style: .date)
                                            .font(Theme.bodyFont)
                                            .foregroundColor(Theme.mutedText)
                                    }
                                    Spacer()
                                    if addToFolderSelections.contains(lecture.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.primaryGreen)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(Theme.mutedText)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                                .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Button(action: {
                guard
                    let folder = addToFolderTarget,
                    !addToFolderSelections.isEmpty
                else { return }
                for lectureId in addToFolderSelections {
                    if let lecture = store.lectures.first(where: { $0.id == lectureId }) {
                        store.moveLecture(lecture, to: folder)
                    }
                }
                showAddToFolderSheet = false
            }) {
                Text("Add")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(addToFolderSelections.isEmpty)
            
            Button("Cancel", role: .cancel) {
                showAddToFolderSheet = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename lecture")
                .font(.title2.bold())
            
            TextField("Lecture title", text: $renameText)
                .textFieldStyle(.roundedBorder)
            
            Spacer()
            
            Button(action: {
                guard let lecture = selectedLecture else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                store.renameLecture(lecture, to: trimmed)
                showRenameSheet = false
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel", role: .cancel) {
                showRenameSheet = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    private var moveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move to folder")
                .font(.title2.bold())
            
            if store.folders.isEmpty {
                Text("You don't have any folders yet.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.folders) { folder in
                            Button(action: { moveSelection = folder.id }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.name)
                                            .font(Theme.titleFont)
                                            .foregroundColor(.black)
                                        Text("\(lectureCount(for: folder)) lectures")
                                            .font(Theme.bodyFont)
                                            .foregroundColor(Theme.mutedText)
                                    }
                                    Spacer()
                                    if moveSelection == folder.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.primaryGreen)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(Theme.mutedText)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                                .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if let currentFolderId = selectedLecture?.folderId, !currentFolderId.isEmpty {
                Button("Remove from folder") {
                    moveSelection = nil
                    applyMoveSelection()
                }
                .buttonStyle(.bordered)
            }
            
            if isCreatingInlineFolder {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New folder name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g. Ramadan series", text: $inlineFolderName)
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        let trimmed = inlineFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let newId = UUID().uuidString
                        store.createFolder(named: trimmed, folderId: newId)
                        moveSelection = newId
                        inlineFolderName = ""
                        isCreatingInlineFolder = false
                    }) {
                        Text("Create and Select")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Create new folder") {
                    isCreatingInlineFolder = true
                }
                .buttonStyle(.bordered)
            }
            
            Button(action: applyMoveSelection) {
                Text("Confirm")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedLecture == nil)
            
            Button("Cancel", role: .cancel) {
                showMoveSheet = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    private func applyMoveSelection() {
        guard let lecture = selectedLecture else { return }
        let folder = store.folders.first(where: { $0.id == moveSelection })
        store.moveLecture(lecture, to: folder)
        showMoveSheet = false
    }
    
    private var createFolderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create a folder")
                .font(.title2.bold())
            
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
            
            Spacer()
            
            Button(action: {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                store.createFolder(named: trimmed)
                showCreateFolderSheet = false
            }) {
                Text("Create")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel", role: .cancel) {
                showCreateFolderSheet = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

struct PromoBannerView: View {
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upgrade to Premium")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Unlock unlimited audio recordings, transcriptions, summaries and translations.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: onTap) {
                Text("Upgrade Now")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .foregroundColor(Theme.primaryGreen)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.primaryGreen, Theme.secondaryGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(18)
        .shadow(color: Theme.shadow, radius: 10, x: 0, y: 6)
    }
}

struct LectureCardView: View {
    let lecture: Lecture
    
    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(lecture.date) { return "Today" }
        if calendar.isDateInYesterday(lecture.date) { return "Yesterday" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: lecture.date)
    }
    
    private var durationText: String? {
        guard let minutes = lecture.durationMinutes else { return nil }
        return "\(minutes) mins"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.background)
                    .frame(width: 40, height: 40)
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.primaryGreen)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(lecture.title)
                    .font(Theme.titleFont)
                    .foregroundColor(.black)
                
                HStack(spacing: 6) {
                    Text(dateText)
                    if let durationText {
                        Text("•")
                        Text(durationText)
                    }
                }
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}

struct LectureDetailView: View {
    @EnvironmentObject var store: LectureStore
    let lecture: Lecture
    @State private var selectedTab = 0
    @State private var selectedSummaryLanguage: SummaryTranslationLanguage = .english
    @State private var selectedTextSize: TextSizeOption = .medium
    @State private var shareItems: [Any]? = nil
    @State private var isShareSheetPresented = false
    @State private var copyBannerMessage: String? = nil
    
    private let tabs = ["Summary", "Transcript"]
    
    private var displayLecture: Lecture {
        store.lectures.first(where: { $0.id == lecture.id }) ?? lecture
    }
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: displayLecture.date)
    }
    
    private var durationText: String {
        if let minutes = displayLecture.durationMinutes {
            return "\(minutes) mins"
        }
        return "Duration pending"
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(displayLecture.title)
                        .font(Theme.largeTitleFont)
                        .foregroundColor(.black)
                    
                    HStack(spacing: 8) {
                        Label(dateText, systemImage: "calendar")
                        Label(durationText, systemImage: "clock")
                        Label(displayLecture.status.rawValue.capitalized, systemImage: "bolt.horizontal.circle")
                    }
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)

                    LectureAudioPlayerView(audioPath: displayLecture.audioPath)
                    
                    Divider()
                    
                    Picker("Content", selection: $selectedTab) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Text(tabs[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if selectedTab == 0 {
                        SummaryView(
                            summary: selectedSummary,
                            isBaseSummaryReady: displayLecture.summary != nil,
                            isTranslationLoading: isTranslationLoading,
                            translationError: translationError,
                            selectedLanguage: $selectedSummaryLanguage,
                            textSize: $selectedTextSize
                        ) {
                            ExportIconButtons(
                                onCopy: {
                                    guard let text = exportableSummaryText(
                                        for: selectedSummary,
                                        language: selectedSummaryLanguage
                                    ) else { return }
                                    copyToClipboard(text)
                                },
                                onShare: {
                                    guard let text = exportableSummaryText(
                                        for: selectedSummary,
                                        language: selectedSummaryLanguage
                                    ) else { return }
                                    presentShareSheet(with: text)
                                },
                                isDisabled: selectedSummary == nil
                            )
                        }
                        .onAppear {
                            requestTranslationIfNeeded(for: selectedSummaryLanguage)
                        }
                        .onChange(of: selectedSummaryLanguage) { newLanguage in
                            requestTranslationIfNeeded(for: newLanguage)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center) {
                                Text("Transcript")
                                    .font(Theme.titleFont)
                                Spacer()
                                TextSizeToggle(selection: $selectedTextSize)
                                ExportIconButtons(
                                    onCopy: {
                                    guard let text = exportableTranscriptText() else { return }
                                    copyToClipboard(text)
                                },
                                onShare: {
                                    guard let text = exportableTranscriptText() else { return }
                                    presentShareSheet(with: text)
                                },
                                isDisabled: (displayLecture.transcript ?? "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )
                        }
                        Text(displayLecture.transcript ?? "Transcript will appear here once ready.")
                            .font(transcriptBodyFont)
                            .foregroundColor(Theme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Lecture")
            .navigationBarTitleDisplayMode(.inline)
            
            if let message = copyBannerMessage {
                CopyBanner(message: message)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
    }
    
    private var brandFooter: String { "\n\n— Created with Khutbah Notes" }
    
    private var selectedSummary: LectureSummary? {
        summary(for: selectedSummaryLanguage, in: displayLecture)
    }
    
    private var isTranslationLoading: Bool {
        guard selectedSummaryLanguage != .english else { return false }
        let code = selectedSummaryLanguage.rawValue
        return displayLecture.summaryTranslationRequests.contains(code) ||
            displayLecture.summaryTranslationInProgress.contains(code)
    }

    private var transcriptBodyFont: Font {
        .system(size: selectedTextSize.bodySize, weight: .regular, design: .rounded)
    }
    
    private var translationError: String? {
        guard selectedSummaryLanguage != .english else { return nil }
        return displayLecture.summaryTranslationErrors?
            .first(where: { $0.languageCode == selectedSummaryLanguage.rawValue })?
            .message
    }
    
    private func summary(
        for language: SummaryTranslationLanguage,
        in lecture: Lecture
    ) -> LectureSummary? {
        if language == .english {
            return lecture.summary
        }
        return lecture.summaryTranslations?
            .first(where: { $0.languageCode == language.rawValue })?
            .summary
    }
    
    private func requestTranslationIfNeeded(for language: SummaryTranslationLanguage) {
        guard language != .english else { return }
        guard displayLecture.summary != nil else { return }
        guard summary(for: language, in: displayLecture) == nil else { return }
        
        let code = language.rawValue
        if displayLecture.summaryTranslationRequests.contains(code) ||
            displayLecture.summaryTranslationInProgress.contains(code) {
            return
        }
        
        Task {
            await store.requestSummaryTranslation(for: displayLecture, language: language)
        }
    }
    
    private func exportableSummaryText(
        for summary: LectureSummary?,
        language: SummaryTranslationLanguage
    ) -> String? {
        guard let summary else { return nil }
        
        var lines: [String] = []
        let summaryLabel = language == .english ?
            "Summary" :
            "Summary (\(language.label))"
        
        lines.append(displayLecture.title)
        lines.append("\(summaryLabel) • \(dateText)")
        lines.append("")
        lines.append("Main Theme:")
        lines.append(summary.mainTheme.isEmpty ? "Not mentioned" : summary.mainTheme)
        
        if !summary.keyPoints.isEmpty {
            lines.append("")
            lines.append("Key Points:")
            lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
        }
        
        if !summary.explicitAyatOrHadith.isEmpty {
            lines.append("")
            lines.append("Explicit Ayat or Hadith:")
            lines.append(contentsOf: summary.explicitAyatOrHadith.map { "- \($0)" })
        }
        
        if !summary.weeklyActions.isEmpty {
            lines.append("")
            lines.append("Weekly Actions:")
            lines.append(contentsOf: summary.weeklyActions.map { "- \($0)" })
        }
        
        return lines.joined(separator: "\n") + brandFooter
    }
    
    private func exportableTranscriptText() -> String? {
        guard let transcript = displayLecture.transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else { return nil }
        
        var lines: [String] = []
        lines.append("\(displayLecture.title) — Transcript")
        lines.append("Date: \(dateText)")
        lines.append("")
        lines.append(transcript)
        return lines.joined(separator: "\n") + brandFooter
    }
    
    private func presentShareSheet(with text: String) {
        shareItems = [text]
        isShareSheetPresented = true
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation {
            copyBannerMessage = "Copied to clipboard"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation {
                copyBannerMessage = nil
            }
        }
    }
}

struct LectureAudioPlayerView: View {
    let audioPath: String?
    @StateObject private var viewModel = LectureAudioPlayerViewModel()
    private var secondaryControlsEnabled: Bool { viewModel.canPlay && !viewModel.isLoading }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    controlButton(systemName: "gobackward.10") {
                        viewModel.seek(by: -10)
                    }
                    
                    Button(action: { viewModel.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [Theme.primaryGreen.opacity(0.85), Theme.secondaryGreen.opacity(0.9)],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                                .frame(width: 48, height: 48)
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.5 : 1)
                    
                    controlButton(systemName: "goforward.10") {
                        viewModel.seek(by: 10)
                    }
                }
                .disabled(!secondaryControlsEnabled)
                .opacity(secondaryControlsEnabled ? 1 : 0.4)
                
                Spacer()
                
                HStack(spacing: 8) {
                    speedButton(systemName: "minus") {
                        viewModel.adjustRate(by: -0.25)
                    }
                    Text(viewModel.rateLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(minWidth: 48)
                    speedButton(systemName: "plus") {
                        viewModel.adjustRate(by: 0.25)
                    }
                }
                .disabled(!viewModel.canAdjustRate)
                .opacity(viewModel.canAdjustRate ? 1 : 0.5)
            }
            
            Slider(
                value: Binding(
                    get: { viewModel.sliderValue },
                    set: { newValue in viewModel.sliderChanged(to: newValue) }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    viewModel.sliderEditingChanged(isEditing: isEditing)
                }
            )
            .tint(Theme.primaryGreen)
            .disabled(!secondaryControlsEnabled)

            HStack {
                Text(viewModel.elapsedTimeLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.mutedText)
                Spacer()
                Text(viewModel.totalTimeLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.mutedText)
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.primaryGreen.opacity(0.12), Theme.secondaryGreen.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.primaryGreen.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(16)
        .onAppear {
            viewModel.prepareIfNeeded(with: audioPath)
        }
        .onChange(of: audioPath) { newValue in
            viewModel.prepareIfNeeded(with: newValue)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.primaryGreen)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Theme.shadow, radius: 5, x: 0, y: 3)
        }
    }
    
    private func speedButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .clipShape(Circle())
        }
    }
}

@MainActor
final class LectureAudioPlayerViewModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var statusText: String = ""
    @Published private(set) var canPlay = false
    @Published var sliderValue: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    
    var rateLabel: String {
        String(format: "%.2gx", playbackRate)
    }

    var elapsedTimeLabel: String {
        formatTime(currentTime)
    }

    var totalTimeLabel: String {
        duration > 0 ? formatTime(duration) : "--:--"
    }
    
    var canAdjustRate: Bool { canPlay }
    private let missingAudioMessage = "The audio file does not exist or was deleted after 30 days"
    
    private var player: AVPlayer?
    private var endObserver: Any?
    private var timeObserverToken: Any?
    private var currentPath: String?
    private var loadFailed = false
    private var hasAudioPath = false
    private var isScrubbing = false
    
    func prepareIfNeeded(with audioPath: String?) {
        guard audioPath != currentPath || player == nil else { return }
        currentPath = audioPath
        resetPlayerState()
        
        hasAudioPath = audioPath != nil
        loadFailed = false
        statusText = ""
        
        guard let audioPath else { return }
        
        isLoading = true
        
        Storage.storage().reference(withPath: audioPath).downloadURL { [weak self] url, error in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false
                if let url {
                    self.setupPlayer(with: url)
                } else {
                    self.loadFailed = true
                    self.statusText = ""
                    self.canPlay = false
                    print("Error fetching audio URL: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    private func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        playbackRate = 1.0
        canPlay = true
        addEndObserver()
        addTimeObserver()
    }
    
    func togglePlayPause() {
        if isLoading { return }
        
        if !hasAudioPath || loadFailed {
            statusText = missingAudioMessage
            return
        }
        
        guard canPlay, let player else {
            statusText = missingAudioMessage
            return
        }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }
    
    func seek(by seconds: Double) {
        guard canPlay, let player else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        var newTime = current + seconds
        if let duration = player.currentItem?.duration, duration.isNumeric {
            let total = CMTimeGetSeconds(duration)
            newTime = min(max(0, newTime), total)
        } else {
            newTime = max(0, newTime)
        }
        let target = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        updateSlider(to: newTime)
    }
    
    func adjustRate(by delta: Float) {
        let newRate = min(2.0, max(0.5, playbackRate + delta))
        playbackRate = newRate
        if isPlaying {
            player?.rate = newRate
        }
    }
    
    func cleanup() {
        player?.pause()
        removeEndObserver()
        removeTimeObserver()
        player = nil
        canPlay = false
        isPlaying = false
        statusText = ""
        currentPath = nil
        loadFailed = false
        hasAudioPath = false
        duration = 0
        currentTime = 0
        sliderValue = 0
    }
    
    private func resetPlayerState() {
        removeEndObserver()
        removeTimeObserver()
        player?.pause()
        player = nil
        canPlay = false
        isPlaying = false
        loadFailed = false
        duration = 0
        currentTime = 0
        sliderValue = 0
    }
    
    private func addEndObserver() {
        guard let item = player?.currentItem else { return }
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.statusText = ""
                self.player?.seek(to: .zero)
            }
        }
    }
    
    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
    
    private func addTimeObserver() {
        removeTimeObserver()
        guard let player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let currentSeconds = CMTimeGetSeconds(time)
                self.currentTime = currentSeconds
                if let durationTime = player.currentItem?.duration, durationTime.isNumeric {
                    self.duration = CMTimeGetSeconds(durationTime)
                }
                if !self.isScrubbing {
                    self.updateSlider(to: currentSeconds)
                }
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
    }
    
    private func updateSlider(to currentSeconds: Double) {
        guard duration > 0 else {
            sliderValue = 0
            return
        }
        sliderValue = min(max(0, currentSeconds / duration), 1)
    }
    
    func sliderChanged(to newValue: Double) {
        sliderValue = newValue
    }
    
    func sliderEditingChanged(isEditing: Bool) {
        isScrubbing = isEditing
        guard !isEditing, canPlay, let player else { return }
        let targetSeconds = duration * sliderValue
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        updateSlider(to: targetSeconds)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct SummaryView<Actions: View>: View {
    let summary: LectureSummary?
    let isBaseSummaryReady: Bool
    let isTranslationLoading: Bool
    let translationError: String?
    @Binding var selectedLanguage: SummaryTranslationLanguage
    @Binding var textSize: TextSizeOption
    let actions: Actions
    
    init(
        summary: LectureSummary?,
        isBaseSummaryReady: Bool,
        isTranslationLoading: Bool,
        translationError: String?,
        selectedLanguage: Binding<SummaryTranslationLanguage>,
        textSize: Binding<TextSizeOption>,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.summary = summary
        self.isBaseSummaryReady = isBaseSummaryReady
        self.isTranslationLoading = isTranslationLoading
        self.translationError = translationError
        self._selectedLanguage = selectedLanguage
        self._textSize = textSize
        self.actions = actions()
    }
    
    private var isRTL: Bool { selectedLanguage.isRTL }
    
    private var summaryBodyFont: Font {
        if isRTL {
            return rtlFont(size: textSize.bodySize, weight: .regular)
        }
        return .system(size: textSize.bodySize, weight: .regular, design: .rounded)
    }
    
    private var summaryHeadingFont: Font {
        if isRTL {
            return rtlFont(size: textSize.headingSize, weight: .semibold)
        }
        return .system(size: textSize.headingSize, weight: .semibold)
    }
    
    private var textAlignment: TextAlignment { isRTL ? .trailing : .leading }
    private var sectionAlignment: HorizontalAlignment { isRTL ? .trailing : .leading }
    private var frameAlignment: Alignment { isRTL ? .trailing : .leading }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text("Summary")
                    .font(Theme.titleFont)
                Spacer()
                TextSizeToggle(selection: $textSize)
                languageMenu
                actions
            }
            
            Group {
                if let summary {
                    summarySection(title: "Main Theme", content: [summary.mainTheme])
                    summarySection(title: "Key Points", content: summary.keyPoints)
                    summarySection(title: "Explicit Ayat or Hadith",
                                   content: summary.explicitAyatOrHadith)
                    summarySection(title: "Weekly Actions",
                                   content: summary.weeklyActions)
                } else if !isBaseSummaryReady {
                    Text("AI summary will appear here once processed.")
                        .font(summaryBodyFont)
                        .foregroundColor(Theme.mutedText)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isTranslationLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Generating translation...")
                            .font(summaryBodyFont)
                            .foregroundColor(Theme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                } else if let translationError, !translationError.isEmpty {
                    Text("Translation unavailable right now. Please try again later.")
                        .font(summaryBodyFont)
                        .foregroundColor(Theme.mutedText)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Translation will appear here once ready.")
                        .font(summaryBodyFont)
                        .foregroundColor(Theme.mutedText)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.primaryGreen.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
        .padding(.vertical, 4)
    }
    
    private var languageMenu: some View {
        Menu {
            ForEach(SummaryTranslationLanguage.displayOrder) { language in
                Button(language.label) {
                    selectedLanguage = language
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(selectedLanguage.label)
                    .lineLimit(1)
                if isTranslationLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.primaryGreen.opacity(0.18), lineWidth: 1)
            )
        }
        .disabled(!isBaseSummaryReady)
        .opacity(isBaseSummaryReady ? 1 : 0.5)
        .buttonStyle(.plain)
    }
    
    private func rtlFont(size: CGFloat, weight: Font.Weight) -> Font {
        if UIFont(name: "Geeza Pro", size: size) != nil {
            return .custom("Geeza Pro", size: size)
        }
        return .system(size: size, weight: weight)
    }
    
    @ViewBuilder
    private func summarySection(title: String, content: [String]) -> some View {
        VStack(alignment: sectionAlignment, spacing: 6) {
            Text(title)
                .font(summaryHeadingFont)
                .foregroundColor(.black)
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            
            if content.isEmpty {
                Text("None mentioned")
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
                    .multilineTextAlignment(textAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            } else if content.count == 1 {
                Text(content[0])
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
                    .multilineTextAlignment(textAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: sectionAlignment, spacing: 4) {
                    ForEach(content, id: \.self) { item in
                        bulletRow(for: item)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func bulletRow(for item: String) -> some View {
        if isRTL {
            HStack(alignment: .top, spacing: 8) {
                Text(item)
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                Text("•")
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
                Text(item)
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.mutedText)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }
}

struct TextSizeToggle: View {
    @Binding var selection: TextSizeOption
    
    private var indicator: String {
        switch selection {
        case .small:
            return "S"
        case .medium:
            return "M"
        case .large:
            return "L"
        case .extraLarge:
            return "XL"
        }
    }
    
    var body: some View {
        Button {
            selection = selection.next
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                Text(indicator)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.primaryGreen.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text size")
        .accessibilityValue(selection.label)
    }
}

struct ExportIconButtons: View {
    var onCopy: () -> Void
    var onShare: () -> Void
    var isDisabled: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            iconButton(systemName: "doc.on.doc", action: onCopy)
            iconButton(systemName: "square.and.arrow.up", action: onShare)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
    
    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .clipShape(Circle())
                .shadow(color: Theme.primaryGreen.opacity(0.18), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct CopyBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Theme.primaryGreen.opacity(0.95))
                    .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 8, x: 0, y: 6)
            )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LectureStore
    @State private var showPaywall = false
    @State private var showFeedback = false

    private var shouldShowUpgrade: Bool {
        (store.userUsage?.plan ?? "free") != "premium"
    }

    var body: some View {
        NavigationView {
            List {
                if shouldShowUpgrade {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Upgrade to Premium", systemImage: "sparkles")
                        }
                    }
                }

                Section(header: Text("Preferences")) {
                    NavigationLink(destination: NotificationsSettingsView()) {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }

                Section(header: Text("Support")) {
                    Button {
                        showFeedback = true
                    } label: {
                        Label("Feedback", systemImage: "envelope")
                    }
                }

                Section(header: Text("Info")) {
                    NavigationLink(destination: StaticContentView(title: "FAQ", bodyText: PlaceholderCopy.faq)) {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink(destination: StaticContentView(title: "About", bodyText: PlaceholderCopy.about)) {
                        Label("About", systemImage: "info.circle")
                    }
                }

                Section(header: Text("Legal")) {
                    NavigationLink(destination: StaticContentView(title: "Terms of Service", bodyText: PlaceholderCopy.terms)) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    NavigationLink(destination: StaticContentView(title: "Privacy Policy", bodyText: PlaceholderCopy.privacy)) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section(header: Text("Account")) {
                    NavigationLink(destination: DeleteAccountView()) {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showPaywall) {
            OnboardingPaywallView {
                showPaywall = false
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
    }
}

#Preview("Notes") {
    NotesView()
        .environmentObject(LectureStore(seedMockData: true))
}

#Preview("Lecture Card") {
    LectureCardView(lecture: .mock)
        .padding()
        .background(Theme.background)
}
