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
import StoreKit

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
    static let backgroundHighlight = Color(red: 0.99, green: 1.0, blue: 0.99)
    static let backgroundGradient = LinearGradient(
        colors: [background, backgroundHighlight],
        startPoint: .top,
        endPoint: .bottom
    )
    static let cardBackground = Color.white
    static let mutedText = Color(red: 0.43, green: 0.49, blue: 0.46)
    static let shadow = Color.black.opacity(0.08)
    
    static let largeTitleFont = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titleFont = Font.system(.headline, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .rounded)
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
    @State private var lastNonQuranTab: Int? = nil
    @State private var toastMessage: String? = nil
    @State private var toastActionTitle: String? = nil
    @State private var toastAction: (() -> Void)? = nil
    @State private var showPaywall = false
    @State private var dashboardNavigationDepth = 0
    @State private var dashboardNavigationResetToken = UUID()
    @State private var pendingRecordingRouteAction: RecordingRouteAction? = nil
    @State private var isKeyboardVisible = false
    @StateObject private var quranNavigator = QuranNavigationCoordinator()
    @AppStorage("hasSavedRecording") private var hasSavedRecording = false
    @AppStorage(RecordingUserDefaultsKeys.controlAction, store: RecordingDefaults.shared) private var pendingControlActionRaw = ""
    @AppStorage(RecordingUserDefaultsKeys.routeAction, store: RecordingDefaults.shared) private var pendingRouteActionRaw = ""
    @AppStorage(
        DashboardDeepLinkUserDefaultsKeys.pendingDashboardToken,
        store: DashboardDeepLinkDefaults.shared
    ) private var pendingDashboardDeepLinkToken = ""
    @AppStorage(
        LectureDeepLinkUserDefaultsKeys.pendingLectureId,
        store: LectureDeepLinkDefaults.shared
    ) private var pendingLectureDeepLinkIdRaw = ""
    
    private var shouldShowRecordPrompt: Bool {
        !hasSavedRecording && selectedTab == 0 && dashboardNavigationDepth == 0
    }
    
    var body: some View {
        mainContent
        .environmentObject(quranNavigator)
        .onAppear {
            handlePendingActions()
        }
        .onChange(of: selectedTab) { tab in
            if tab != 2 {
                lastNonQuranTab = nil
            }
        }
        .onChange(of: quranNavigator.pendingTarget) { target in
            guard target != nil else { return }
            if selectedTab != 2 {
                lastNonQuranTab = selectedTab
            }
            selectedTab = 2
        }
        .onChange(of: pendingControlActionRaw) { _ in
            handlePendingControlAction()
        }
        .onChange(of: pendingRouteActionRaw) { _ in
            handlePendingRouteAction()
        }
        .onChange(of: pendingDashboardDeepLinkToken) { _ in
            handlePendingDashboardDeepLink()
        }
        .onChange(of: pendingLectureDeepLinkIdRaw) { _ in
            handlePendingLectureDeepLinkTabSwitch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            tabContent
            recordButton
            recordPromptOverlay
            toastOverlay
        }
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            NotesView(
                selectedTab: $selectedTab,
                dashboardNavigationDepth: $dashboardNavigationDepth,
                onShowToast: { message in
                    showToast(message)
                }
            )
                .id(dashboardNavigationResetToken)
                .tabItem {
                    Image(systemName: "book.closed.fill")
                    Text("Notes")
                }
                .tag(0)
            
            RecordLectureView(
                selectedTab: $selectedTab,
                pendingRouteAction: $pendingRecordingRouteAction,
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

            QuranView(
                showBackToLecture: lastNonQuranTab != nil,
                onBackToLecture: handleBackToLecture
            )
                .tabItem {
                    Image(systemName: "book.closed.fill")
                    Text("Quran")
                }
                .tag(2)
        }
        .tint(Theme.primaryGreen)
        .sheet(isPresented: $showPaywall) {
            OnboardingPaywallView {
                showPaywall = false
            }
        }
    }

    private var recordButton: some View {
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
        .opacity(isKeyboardVisible ? 0 : 1)
        .allowsHitTesting(!isKeyboardVisible)
        .accessibilityHidden(isKeyboardVisible)
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
    }

    @ViewBuilder
    private var recordPromptOverlay: some View {
        if shouldShowRecordPrompt {
            DashboardRecordPrompt()
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
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

    private func handlePendingActions() {
        handlePendingControlAction()
        handlePendingRouteAction()
        handlePendingDashboardDeepLink()
        handlePendingLectureDeepLinkTabSwitch()
    }

    private func handlePendingControlAction() {
        guard let action = RecordingControlAction(rawValue: pendingControlActionRaw) else { return }
        Task { @MainActor in
            RecordingControlCenter.shared.handle(action, shouldRouteToSaveCard: action == .stop)
        }
        pendingControlActionRaw = ""
    }

    private func handlePendingRouteAction() {
        guard let action = RecordingRouteAction(rawValue: pendingRouteActionRaw) else { return }
        selectedTab = 1
        pendingRecordingRouteAction = action
        pendingRouteActionRaw = ""
    }

    private func handlePendingLectureDeepLinkTabSwitch() {
        let trimmed = pendingLectureDeepLinkIdRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTab = 0
    }

    private func handlePendingDashboardDeepLink() {
        let trimmed = pendingDashboardDeepLinkToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTab = 0
        lastNonQuranTab = nil
        dashboardNavigationDepth = 0
        dashboardNavigationResetToken = UUID()
        pendingDashboardDeepLinkToken = ""
    }

    private func handleBackToLecture() {
        guard let tab = lastNonQuranTab else { return }
        selectedTab = tab
        lastNonQuranTab = nil
    }

    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
            toastActionTitle = nil
            toastAction = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                toastMessage = nil
                toastActionTitle = nil
                toastAction = nil
            }
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var store: LectureStore
    @Binding var selectedTab: Int
    @Binding var dashboardNavigationDepth: Int
    let onShowToast: ((String) -> Void)?
    @State private var selectedSegment = 0
    @State private var showRenameSheet = false
    @State private var showMoveSheet = false
    @State private var showCreateFolderSheet = false
    @State private var showDeleteAlert = false
    @State private var showRenameFolderSheet = false
    @State private var showDeleteFolderAlert = false
    @State private var selectedLecture: Lecture?
    @State private var renameText = ""
    @State private var folderRenameText = ""
    @State private var moveSelection: String?
    @State private var newFolderName = ""
    @State private var inlineFolderName = ""
    @State private var isCreatingInlineFolder = false
    @State private var pendingDeleteLecture: Lecture?
    @State private var pendingRenameFolder: Folder?
    @State private var pendingDeleteFolder: Folder?
    @State private var showAddToFolderSheet = false
    @State private var addToFolderTarget: Folder?
    @State private var addToFolderSelections: Set<String> = []
    @State private var showPaywall = false
    @State private var showSettings = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchQuery = ""
    @State private var activeSearchQuery = ""
    @State private var showSearchResults = false
    @State private var deepLinkLecture: Lecture?
    @State private var showDeepLinkLecture = false
    @State private var isRamadanGiftBannerDismissed = false
    @AppStorage(
        LectureDeepLinkUserDefaultsKeys.pendingLectureId,
        store: LectureDeepLinkDefaults.shared
    ) private var pendingLectureDeepLinkIdRaw = ""

    init(
        selectedTab: Binding<Int>,
        dashboardNavigationDepth: Binding<Int>,
        onShowToast: ((String) -> Void)? = nil
    ) {
        _selectedTab = selectedTab
        _dashboardNavigationDepth = dashboardNavigationDepth
        self.onShowToast = onShowToast
    }
    
    private let segments = ["All Notes", "Folders"]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFreeUser: Bool {
        (store.userUsage?.plan ?? "free") != "premium"
    }

    private var shouldShowRamadanGiftBanner: Bool {
        guard isFreeUser, !isRamadanGiftBannerDismissed else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let cutoffComponents = DateComponents(year: 2026, month: 3, day: 21)
        guard let cutoffDate = calendar.date(from: cutoffComponents) else { return false }
        return Date() < cutoffDate
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
            LectureRenameSheet(
                lecture: selectedLecture,
                renameText: $renameText,
                isPresented: $showRenameSheet
            )
        }
        .sheet(isPresented: $showRenameFolderSheet, onDismiss: {
            folderRenameText = ""
            pendingRenameFolder = nil
        }) {
            renameFolderSheet
        }
        .sheet(isPresented: $showMoveSheet, onDismiss: {
            moveSelection = nil
            isCreatingInlineFolder = false
            inlineFolderName = ""
        }) {
            LectureMoveSheet(
                lecture: selectedLecture,
                moveSelection: $moveSelection,
                isCreatingInlineFolder: $isCreatingInlineFolder,
                inlineFolderName: $inlineFolderName,
                isPresented: $showMoveSheet
            )
        }
        .sheet(isPresented: $showCreateFolderSheet, onDismiss: { newFolderName = "" }) {
            createFolderSheet
        }
        .sheet(isPresented: $showAddToFolderSheet, onDismiss: {
            addToFolderSelections = []
            addToFolderTarget = nil
        }) {
            LectureAddToFolderSheet(
                targetFolder: $addToFolderTarget,
                selections: $addToFolderSelections,
                isPresented: $showAddToFolderSheet
            )
        }
        .sheet(isPresented: $showPaywall) {
            OnboardingPaywallView {
                showPaywall = false
            }
        }
        .onAppear {
            handlePendingLectureDeepLink()
        }
        .onChange(of: pendingLectureDeepLinkIdRaw) { _ in
            handlePendingLectureDeepLink()
        }
        .onChange(of: store.lectures) { _ in
            handlePendingLectureDeepLink()
        }
        .onChange(of: store.hasLoadedLectures) { _ in
            handlePendingLectureDeepLink()
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
        .alert("Delete folder?", isPresented: $showDeleteFolderAlert) {
            Button("Delete", role: .destructive) {
                if let folder = pendingDeleteFolder {
                    store.deleteFolder(folder)
                }
                pendingDeleteFolder = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteFolder = nil
            }
        } message: {
            Text("Delete folder and remove its lectures from the folder?")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if shouldShowRamadanGiftBanner {
                        RamadanGiftBannerView {
                            isRamadanGiftBannerDismissed = true
                        }
                    }
                    header
                    if isFreeUser {
                        PromoBannerView {
                            showPaywall = true
                        }
                    }
                    searchBar
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
            .dismissKeyboardOnScroll()
            hiddenNavigationLinks
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var hiddenNavigationLinks: some View {
        Group {
            NavigationLink(
                destination: deepLinkLectureDestination,
                isActive: $showDeepLinkLecture
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .hidden()
            NavigationLink(
                destination: NavigationDepthTracker(depth: $dashboardNavigationDepth) {
                    SearchResultsView(
                        query: activeSearchQuery,
                        selectedTab: $selectedTab,
                        dashboardNavigationDepth: $dashboardNavigationDepth
                    )
                },
                isActive: $showSearchResults
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .hidden()
            NavigationLink(
                destination: NavigationDepthTracker(depth: $dashboardNavigationDepth) {
                    SettingsView()
                },
                isActive: $showSettings
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .hidden()
        }
    }

    @ViewBuilder
    private var deepLinkLectureDestination: some View {
        if let lecture = deepLinkLecture {
            NavigationDepthTracker(depth: $dashboardNavigationDepth) {
                LectureDetailView(
                    lecture: lecture,
                    selectedRootTab: $selectedTab
                )
            }
        } else {
            EmptyView()
        }
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
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.primaryGreen)
                        .frame(width: 38, height: 38)
                        .background(Theme.primaryGreen.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Theme.primaryGreen.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            Text("As-salamu alaikum")
                .font(.subheadline)
                .foregroundColor(Theme.mutedText)
        }
    }

    
    
    private var segmentPicker: some View {
        PillSegmentedControl(segments: segments, selection: $selectedSegment)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.mutedText)
            TextField("Search saved summaries and transcripts", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.mutedText.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            Button {
                performSearch()
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
            .disabled(trimmedSearchQuery.isEmpty)
            .opacity(trimmedSearchQuery.isEmpty ? 0.6 : 1)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 4)
        .accessibilityLabel("Search summaries and transcripts")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isSearchFocused = false
                }
            }
        }
    }
    
    private var lectureList: some View {
        VStack(spacing: 12) {
            ForEach(store.lectures) { lecture in
                ZStack(alignment: .topTrailing) {
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
                        ZStack(alignment: .topTrailing) {
                            NavigationLink {
                                NavigationDepthTracker(depth: $dashboardNavigationDepth) {
                                    FolderDetailView(
                                        folder: folder,
                                        lectures: lectures(in: folder),
                                        selectedTab: $selectedTab,
                                        onRename: { lecture in startRename(for: lecture) },
                                        onMove: { lecture in startMove(for: lecture) },
                                        onDelete: { lecture in
                                            pendingDeleteLecture = lecture
                                            showDeleteAlert = true
                                        },
                                        onAddLecture: {
                                            addToFolderTarget = folder
                                            showAddToFolderSheet = true
                                        },
                                        onRenameFolder: { folder in
                                            startRenameFolder(folder)
                                        },
                                        onDeleteFolder: { folder in
                                            startDeleteFolder(folder)
                                        }
                                    )
                                }
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
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardBackground)
                                .cornerRadius(14)
                                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            
                            Menu {
                                Button("Rename") { startRenameFolder(folder) }
                                Button(role: .destructive) {
                                    startDeleteFolder(folder)
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
        }
    }
    
    private func startRename(for lecture: Lecture) {
        selectedLecture = lecture
        renameText = lecture.title
        showRenameSheet = true
    }

    private func startRenameFolder(_ folder: Folder) {
        pendingRenameFolder = folder
        folderRenameText = folder.name
        showRenameFolderSheet = true
    }

    private func startDeleteFolder(_ folder: Folder) {
        pendingDeleteFolder = folder
        showDeleteFolderAlert = true
    }

    private func performSearch() {
        let trimmed = trimmedSearchQuery
        guard !trimmed.isEmpty else { return }
        activeSearchQuery = trimmed
        showSearchResults = true
    }

    private func handlePendingLectureDeepLink() {
        let trimmed = pendingLectureDeepLinkIdRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let lecture = store.lectures.first(where: { $0.id == trimmed }) {
            selectedTab = 0
            deepLinkLecture = lecture
            showDeepLinkLecture = true
            pendingLectureDeepLinkIdRaw = ""
            return
        }

        guard store.hasLoadedLectures else { return }
        pendingLectureDeepLinkIdRaw = ""
        onShowToast?("We couldn't find that lecture. It may have been deleted.")
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

    private var renameFolderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename folder")
                .font(.title2.bold())
            
            TextField("Folder name", text: $folderRenameText)
                .textFieldStyle(.roundedBorder)
            
            Spacer()
            
            Button(action: {
                guard let folder = pendingRenameFolder else { return }
                let trimmed = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                store.renameFolder(folder, newName: trimmed)
                showRenameFolderSheet = false
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel", role: .cancel) {
                showRenameFolderSheet = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
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

struct LectureRenameSheet: View {
    @EnvironmentObject var store: LectureStore
    let lecture: Lecture?
    @Binding var renameText: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename lecture")
                .font(.title2.bold())

            TextField("Lecture title", text: $renameText)
                .textFieldStyle(.roundedBorder)

            Spacer()

            Button(action: renameLecture) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel", role: .cancel) {
                isPresented = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func renameLecture() {
        guard let lecture else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.renameLecture(lecture, to: trimmed)
        isPresented = false
    }
}

struct LectureMoveSheet: View {
    @EnvironmentObject var store: LectureStore
    let lecture: Lecture?
    @Binding var moveSelection: String?
    @Binding var isCreatingInlineFolder: Bool
    @Binding var inlineFolderName: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move to folder")
                .font(.title2.bold())

            if store.folders.isEmpty {
                Text("You don't have any folders yet.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            } else {
                FolderSelectionList(selectedFolderId: $moveSelection)
            }

            if let currentFolderId = lecture?.folderId, !currentFolderId.isEmpty {
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
                    Button(action: createInlineFolder) {
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
            .disabled(lecture == nil)

            Button("Cancel", role: .cancel) {
                isPresented = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func applyMoveSelection() {
        guard let lecture else { return }
        let folder = store.folders.first(where: { $0.id == moveSelection })
        store.moveLecture(lecture, to: folder)
        isPresented = false
    }

    private func createInlineFolder() {
        let trimmed = inlineFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newId = UUID().uuidString
        store.createFolder(named: trimmed, folderId: newId)
        moveSelection = newId
        inlineFolderName = ""
        isCreatingInlineFolder = false
    }
}

struct LectureAddToFolderSheet: View {
    @EnvironmentObject var store: LectureStore
    @Binding var targetFolder: Folder?
    @Binding var selections: Set<String>
    @Binding var isPresented: Bool

    private var targetFolderId: Binding<String?> {
        Binding(
            get: { targetFolder?.id },
            set: { newValue in
                targetFolder = store.folders.first(where: { $0.id == newValue })
            }
        )
    }

    private var canSubmit: Bool {
        targetFolder != nil && !selections.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to \(targetFolder?.name ?? "folder")")
                .font(.title2.bold())

            if targetFolder == nil {
                if store.folders.isEmpty {
                    Text("You don't have any folders yet.")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.mutedText)
                } else {
                    Text("Choose a folder")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.mutedText)
                    FolderSelectionList(selectedFolderId: targetFolderId)
                }
            }

            if store.lectures.isEmpty {
                Text("No lectures available.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.lectures) { lecture in
                            Button(action: {
                                if selections.contains(lecture.id) {
                                    selections.remove(lecture.id)
                                } else {
                                    selections.insert(lecture.id)
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
                                    if selections.contains(lecture.id) {
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

            Button(action: addLecturesToFolder) {
                Text("Add")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            Button("Cancel", role: .cancel) {
                isPresented = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func addLecturesToFolder() {
        guard let folder = targetFolder, !selections.isEmpty else { return }
        for lectureId in selections {
            if let lecture = store.lectures.first(where: { $0.id == lectureId }) {
                store.moveLecture(lecture, to: folder)
            }
        }
        isPresented = false
    }
}

private struct FolderSelectionList: View {
    @EnvironmentObject var store: LectureStore
    @Binding var selectedFolderId: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.folders) { folder in
                    Button(action: { selectedFolderId = folder.id }) {
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
                            if selectedFolderId == folder.id {
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

    private func lectureCount(for folder: Folder) -> Int {
        store.lectures.filter { $0.folderId == folder.id }.count
    }
}

struct NavigationDepthTracker<Content: View>: View {
    @Binding var depth: Int
    let content: Content
    @State private var isActive = false
    
    init(depth: Binding<Int>, @ViewBuilder content: () -> Content) {
        _depth = depth
        self.content = content()
    }
    
    var body: some View {
        content
            .onAppear {
                guard !isActive else { return }
                isActive = true
                depth += 1
            }
            .onDisappear {
                guard isActive else { return }
                isActive = false
                depth = max(0, depth - 1)
            }
    }
}

private struct DashboardRecordPrompt: View {
    @State private var animateArrow = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Click here to start recording!")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.primaryGreen)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.95))
                        .shadow(color: Theme.primaryGreen.opacity(0.15),
                                radius: 8,
                                x: 0,
                                y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.primaryGreen.opacity(0.2), lineWidth: 1)
                )
            Image(systemName: "arrow.down")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.primaryGreen)
                .offset(y: animateArrow ? 6 : -6)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                           value: animateArrow)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 90)
        .onAppear {
            animateArrow = false
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                animateArrow = true
            }
        }
        .allowsHitTesting(false)
    }
}

struct PromoBannerView: View {
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support Khutbah Notes")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Upgrade to unlock unlimited minutes, transcripts, and summaries.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: onTap) {
                Text("Go Premium")
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

struct RamadanGiftBannerView: View {
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.primaryGreen)

            Text("Ramadan gift! Enjoy 60 minutes full access.")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.primaryGreen)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.primaryGreen)
                    .frame(width: 22, height: 22)
                    .background(Theme.primaryGreen.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Ramadan gift banner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primaryGreen.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.primaryGreen.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
    }
}

struct LectureCardView: View {
    @EnvironmentObject var store: LectureStore
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

    private var isUploading: Bool {
        store.activeUploads.contains(lecture.id)
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

            if isUploading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}

private struct StoredLectureIDSet: RawRepresentable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init() {
        rawValue = "[]"
    }

    init(ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids)),
           let encoded = String(data: data, encoding: .utf8) {
            rawValue = encoded
        } else {
            rawValue = "[]"
        }
    }

    var ids: Set<String> {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }
}

struct LectureDetailView: View {
    @EnvironmentObject var store: LectureStore
    @Environment(\.dismiss) private var dismiss
    let lecture: Lecture
    @Binding var selectedRootTab: Int
    @State private var selectedContentTab = 0
    @State private var selectedSummaryLanguage: SummaryTranslationLanguage = .english
    @State private var selectedTextSize: TextSizeOption = .medium
    @State private var notesText: String = ""
    @State private var showRenameSheet = false
    @State private var showMoveSheet = false
    @State private var showAddToFolderSheet = false
    @State private var renameText = ""
    @State private var moveSelection: String?
    @State private var addToFolderTarget: Folder?
    @State private var addToFolderSelections: Set<String> = []
    @State private var isCreatingInlineFolder = false
    @State private var inlineFolderName = ""
    @State private var shareItems: [Any]? = nil
    @State private var isShareSheetPresented = false
    @State private var copyBannerMessage: String? = nil
    @State private var summaryRetryNow = Date()
    private let summaryRetryTimer =
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @AppStorage("didRequestDemoReview") private var didRequestDemoReview = false
    @AppStorage("realSummaryReviewCountedLectureIDs") private var realSummaryReviewCountedLectureIDs = StoredLectureIDSet()
    @AppStorage("didRequestRealSummaryReview") private var didRequestRealSummaryReview = false
    @FocusState private var isNotesFocused: Bool
    
    private let tabs = ["Summary", "Transcript", "Notes"]
    private let failureMessage =
        "Transcription failed. Try recording in a quieter space or closer to the speaker."
    private let noSpeechDetectedMessage = "No speech detected in this recording."
    private let noSpeechTitle = "No Speech Detected"
    private let noSpeechFailureMessage =
        "We couldn't hear any speech. Try again closer to the mic or in a quieter space."
    private let refundMessage = "Any charged minutes were refunded."
    private let uploadRetryMessage = "Upload failed - tap to retry"
    
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

    private var isTranscriptionFailed: Bool {
        displayLecture.status == .failed && !displayLecture.hasTranscript
    }

    private var isNoSpeechDetected: Bool {
        if let errorMessage = displayLecture.errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            return errorMessage == noSpeechDetectedMessage
        }
        return false
    }
    
    private var shouldShowSummaryRetry: Bool {
        displayLecture.shouldShowSummaryRetry(now: summaryRetryNow)
    }
    
    private var summaryStatusMessage: String? {
        if displayLecture.status == .failed && displayLecture.hasTranscript {
            if let errorMessage = displayLecture.errorMessage?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !errorMessage.isEmpty {
                return "Summary failed: \(errorMessage)"
            }
            return "Summary failed. Tap retry to try again."
        }
        
        if displayLecture.status == .summarizing && shouldShowSummaryRetry {
            return "Summary is taking longer than usual. You can retry now."
        }
        
        return nil
    }
    
    private var isTranscriptProcessing: Bool {
        !displayLecture.hasTranscript && (
            displayLecture.status == .processing
                || displayLecture.status == .summarizing
        )
    }
    
    private var transcriptStatusMessage: String {
        switch displayLecture.status {
        case .summarizing:
            return "Finalizing transcript..."
        default:
            return "Transcribing audio..."
        }
    }

    private var failedContentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.primaryGreen)
                Text(isNoSpeechDetected ? noSpeechTitle : "Transcription Failed")
                    .font(Theme.titleFont)
                    .foregroundColor(.black)
            }

            Text(isNoSpeechDetected ? noSpeechFailureMessage : failureMessage)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = displayLecture.errorMessage,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if errorMessage == uploadRetryMessage {
                    Button {
                        store.retryLectureUpload(lectureId: displayLecture.id)
                    } label: {
                        Text("Reason: \(errorMessage)")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                } else if !isNoSpeechDetected {
                    Text("Reason: \(errorMessage)")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(refundMessage)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)

            Button {
                selectedRootTab = 1
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Re-record")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.primaryGreen.opacity(0.12))
                .foregroundColor(Theme.primaryGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Spacer()
                TextSizeToggle(selection: $selectedTextSize, showsBackground: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(Theme.titleFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Theme.primaryGreen, Theme.secondaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                ZStack(alignment: .topLeading) {
                    if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add your notes...")
                            .font(transcriptBodyFont)
                            .foregroundColor(Theme.mutedText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notesText)
                        .font(transcriptBodyFont)
                        .foregroundColor(.black)
                        .focused($isNotesFocused)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 220)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    isNotesFocused = false
                                }
                            }
                        }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
            .padding(.vertical, 4)
        }
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
                    
                    PillSegmentedControl(segments: tabs, selection: $selectedContentTab)

                    if isTranscriptionFailed && selectedContentTab != 2 {
                        failedContentCard
                    } else if selectedContentTab == 0 {
                        SummaryView(
                            lectureId: displayLecture.id,
                            summary: selectedSummary,
                            isBaseSummaryReady: displayLecture.summary != nil,
                            isTranslationLoading: isTranslationLoading,
                            translationError: translationError,
                            statusMessage: summaryStatusMessage,
                            showRetrySummary: shouldShowSummaryRetry,
                            onRetrySummary: shouldShowSummaryRetry ? {
                                Task {
                                    await store.retrySummary(for: displayLecture)
                                }
                            } : nil,
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
                            if displayLecture.isDemo {
                                guard !didRequestDemoReview else { return }
                                didRequestDemoReview = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    requestReview()
                                }
                            }

                            guard displayLecture.summary != nil else { return }
                            guard !displayLecture.isDemo else { return }
                            var countedIDs = realSummaryReviewCountedLectureIDs.ids
                            guard !countedIDs.contains(displayLecture.id) else { return }
                            countedIDs.insert(displayLecture.id)
                            realSummaryReviewCountedLectureIDs = StoredLectureIDSet(ids: countedIDs)
                            guard countedIDs.count == 2, !didRequestRealSummaryReview else { return }
                            didRequestRealSummaryReview = true
                            DispatchQueue.main.async {
                                requestReview()
                            }
                        }
                        .onChange(of: selectedSummaryLanguage) { newLanguage in
                            requestTranslationIfNeeded(for: newLanguage)
                        }
                    } else if selectedContentTab == 1 {
                        let transcriptText = displayLecture.transcriptFormatted ?? displayLecture.transcript
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 10) {
                                Spacer()
                                TextSizeToggle(selection: $selectedTextSize, showsBackground: false)
                                ExportIconButtons(
                                    onCopy: {
                                        guard let text = exportableTranscriptText() else { return }
                                        copyToClipboard(text)
                                    },
                                    onShare: {
                                        guard let text = exportableTranscriptText() else { return }
                                        presentShareSheet(with: text)
                                    },
                                    isDisabled: (transcriptText ?? "")
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.vertical, 1)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Transcript")
                                    .font(Theme.titleFont)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                
                                if isTranscriptProcessing {
                                    HStack(alignment: .center, spacing: 8) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                        Text(transcriptStatusMessage)
                                            .font(transcriptBodyFont)
                                            .foregroundColor(.black)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                } else {
                                    Text(transcriptText ?? "Transcript will appear here once ready.")
                                        .font(transcriptBodyFont)
                                        .foregroundColor(.black)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                            .padding(.vertical, 4)
                        }
                    } else {
                        notesCard
                    }
                }
                .padding()
            }
            .dismissKeyboardOnScroll()
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Rename Lecture…") { startRename() }
                        Button("Move to Folder…") { startMove() }
                        Button("Add to Folder…") { startAddToFolder() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.mutedText)
                    }
                }
            }
            
            if let message = copyBannerMessage {
                CopyBanner(message: message)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(summaryRetryTimer) { date in
            summaryRetryNow = date
        }
        .onAppear {
            notesText = displayLecture.notes ?? ""
        }
        .onChange(of: displayLecture.notes ?? "") { newValue in
            guard !isNotesFocused else { return }
            if notesText != newValue {
                notesText = newValue
            }
        }
        .onChange(of: notesText) { newValue in
            guard isNotesFocused else { return }
            store.updateNotes(for: displayLecture.id, notes: newValue)
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
        .sheet(isPresented: $showRenameSheet, onDismiss: { renameText = "" }) {
            LectureRenameSheet(
                lecture: displayLecture,
                renameText: $renameText,
                isPresented: $showRenameSheet
            )
        }
        .sheet(isPresented: $showMoveSheet, onDismiss: {
            moveSelection = nil
            isCreatingInlineFolder = false
            inlineFolderName = ""
        }) {
            LectureMoveSheet(
                lecture: displayLecture,
                moveSelection: $moveSelection,
                isCreatingInlineFolder: $isCreatingInlineFolder,
                inlineFolderName: $inlineFolderName,
                isPresented: $showMoveSheet
            )
        }
        .sheet(isPresented: $showAddToFolderSheet, onDismiss: {
            addToFolderSelections = []
            addToFolderTarget = nil
        }) {
            LectureAddToFolderSheet(
                targetFolder: $addToFolderTarget,
                selections: $addToFolderSelections,
                isPresented: $showAddToFolderSheet
            )
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

    private func requestReview() {
        let request = {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            SKStoreReviewController.requestReview(in: scene)
        }
        if Thread.isMainThread {
            request()
        } else {
            DispatchQueue.main.async(execute: request)
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
        
        let explicitAyahItems = explicitAyahCitations(from: summary.explicitAyatOrHadith)
        if !explicitAyahItems.isEmpty {
            lines.append("")
            lines.append("Explicit Ayahs Mentioned:")
            lines.append(contentsOf: explicitAyahItems.map { "- \($0)" })
        }
        
        if !summary.weeklyActions.isEmpty {
            lines.append("")
            lines.append("Weekly Actions:")
            lines.append(contentsOf: summary.weeklyActions.map { "- \($0)" })
        }
        
        return lines.joined(separator: "\n") + brandFooter
    }

    private func explicitAyahCitations(from items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && QuranCitationParser.parse($0) != nil }
    }
    
    private func exportableTranscriptText() -> String? {
        guard let transcript = (displayLecture.transcriptFormatted ?? displayLecture.transcript)?
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

    private func startRename() {
        renameText = displayLecture.title
        showRenameSheet = true
    }

    private func startMove() {
        moveSelection = displayLecture.folderId
        isCreatingInlineFolder = false
        inlineFolderName = ""
        showMoveSheet = true
    }

    private func startAddToFolder() {
        addToFolderSelections = [displayLecture.id]
        addToFolderTarget = store.folders.first(where: { $0.id == displayLecture.folderId })
        showAddToFolderSheet = true
    }
}

private extension View {
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
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
    private let audioSession = AVAudioSession.sharedInstance()
    private var endObserver: Any?
    private var timeObserverToken: Any?
    private var currentPath: String?
    private var loadFailed = false
    private var hasAudioPath = false
    private var isScrubbing = false
    private var isAudioSessionActive = false
    
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
            deactivateAudioSessionIfNeeded()
        } else {
            activateAudioSessionForPlayback()
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
        deactivateAudioSessionIfNeeded()
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
        deactivateAudioSessionIfNeeded()
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
                self.deactivateAudioSessionIfNeeded()
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

    private func activateAudioSessionForPlayback() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true, options: [])
            isAudioSessionActive = true
        } catch {
            print("Failed to activate audio session for playback: \(error)")
        }
    }

    private func deactivateAudioSessionIfNeeded() {
        guard isAudioSessionActive else { return }
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
        } catch {
            print("Failed to deactivate audio session after playback: \(error)")
        }
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
    let lectureId: String?
    let summary: LectureSummary?
    let isBaseSummaryReady: Bool
    let isTranslationLoading: Bool
    let translationError: String?
    let statusMessage: String?
    let showRetrySummary: Bool
    let onRetrySummary: (() -> Void)?
    @Binding var selectedLanguage: SummaryTranslationLanguage
    @Binding var textSize: TextSizeOption
    let actions: Actions
    @State private var shareComposerData: ShareComposerData? = nil
    @EnvironmentObject private var quranNavigator: QuranNavigationCoordinator
    
    init(
        lectureId: String? = nil,
        summary: LectureSummary?,
        isBaseSummaryReady: Bool,
        isTranslationLoading: Bool,
        translationError: String?,
        statusMessage: String? = nil,
        showRetrySummary: Bool = false,
        onRetrySummary: (() -> Void)? = nil,
        selectedLanguage: Binding<SummaryTranslationLanguage>,
        textSize: Binding<TextSizeOption>,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.lectureId = lectureId
        self.summary = summary
        self.isBaseSummaryReady = isBaseSummaryReady
        self.isTranslationLoading = isTranslationLoading
        self.translationError = translationError
        self.statusMessage = statusMessage
        self.showRetrySummary = showRetrySummary
        self.onRetrySummary = onRetrySummary
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
            HStack(alignment: .center, spacing: 12) {
                Spacer()
                TextSizeToggle(selection: $textSize, showsBackground: false)
                languageMenu
                actions
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 1)
            
            Group {
                if let summary {
                    let explicitAyahItems = summary.explicitAyatOrHadith
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && QuranCitationParser.parse($0) != nil }
                    VStack(alignment: sectionAlignment, spacing: 18) {
                        summarySection(title: "Main Theme", content: [summary.mainTheme])
                        summarySection(title: "Key Points",
                                       content: summary.keyPoints,
                                       showsDividers: true,
                                       shareSection: .keyPoints)
                        summarySection(title: "Weekly Actions",
                                       content: summary.weeklyActions,
                                       showsDividers: true,
                                       shareSection: .weeklyActions)
                        summarySection(title: "Explicit Ayahs Mentioned",
                                       content: explicitAyahItems,
                                       hideWhenEmpty: true,
                                       showsDividers: true,
                                       customContent: { items in
                                           AnyView(explicitAyatOrHadithContent(items))
                                       })
                    }
                } else if !isBaseSummaryReady {
                    VStack(alignment: sectionAlignment, spacing: 12) {
                        HStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text(statusMessage ?? "Generating summary...")
                                .font(summaryBodyFont)
                                .foregroundColor(Theme.mutedText)
                        }
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        
                        if showRetrySummary, let onRetrySummary {
                            SummaryRetryButton(action: onRetrySummary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $shareComposerData) { data in
            ShareComposerView(
                section: data.section,
                items: data.items,
                lockedId: data.lockedId
            )
        }
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
    private func summarySection(
        title: String,
        content: [String],
        hideWhenEmpty: Bool = false,
        showsDividers: Bool = false,
        shareSection: ShareSection? = nil,
        customContent: (([String]) -> AnyView)? = nil
    ) -> some View {
        Group {
            if hideWhenEmpty && content.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: sectionAlignment, spacing: 12) {
                    Text(title)
                        .font(summaryHeadingFont)
                        .foregroundColor(.white)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    if let customContent {
                        customContent(content)
                    } else if content.isEmpty {
                        Text("None mentioned")
                            .font(summaryBodyFont)
                            .foregroundColor(.black)
                            .multilineTextAlignment(textAlignment)
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                    } else if content.count == 1 && shareSection == nil {
                        Text(content[0])
                            .font(summaryBodyFont)
                            .foregroundColor(.black)
                            .multilineTextAlignment(textAlignment)
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: sectionAlignment, spacing: 4) {
                            ForEach(content.indices, id: \.self) { index in
                                bulletRow(
                                    for: content[index],
                                    index: index,
                                    content: content,
                                    shareSection: shareSection
                                )
                                if showsDividers && index < content.count - 1 {
                                    summarySeparator
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.primaryGreen.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
            }
        }
    }

    private var summarySeparator: some View {
        Rectangle()
            .fill(Theme.mutedText.opacity(0.35))
            .frame(height: 0.5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    @ViewBuilder
    private func explicitAyatOrHadithContent(_ content: [String]) -> some View {
        let citations = content.compactMap { item -> (String, QuranCitation)? in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let citation = QuranCitationParser.parse(trimmed) else {
                return nil
            }
            return (trimmed, citation)
        }
        VStack(alignment: sectionAlignment, spacing: 6) {
            ForEach(citations.indices, id: \.self) { index in
                let item = citations[index]
                citationButton(label: item.0, citation: item.1)
            }
        }
    }

    private func citationButton(label: String, citation: QuranCitation) -> some View {
        Button {
            quranNavigator.requestNavigation(
                to: QuranCitationTarget(surahId: citation.surahId, ayah: citation.ayah)
            )
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(summaryBodyFont)
                    .foregroundColor(Theme.primaryGreen)
                    .multilineTextAlignment(textAlignment)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.primaryGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.primaryGreen.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityLabel("Open \(label)")
    }
    
    @ViewBuilder
    private func bulletRow(
        for item: String,
        index: Int,
        content: [String],
        shareSection: ShareSection?
    ) -> some View {
        if let shareSection {
            if isRTL {
                HStack(alignment: .top, spacing: 8) {
                    shareButton(for: shareSection, content: content, index: index)
                    Spacer(minLength: 8)
                    Text(item)
                        .font(summaryBodyFont)
                        .foregroundColor(.black)
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("•")
                        .font(summaryBodyFont)
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(summaryBodyFont)
                        .foregroundColor(.black)
                    Text(item)
                        .font(summaryBodyFont)
                        .foregroundColor(.black)
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    shareButton(for: shareSection, content: content, index: index)
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        } else if isRTL {
            HStack(alignment: .top, spacing: 8) {
                Text(item)
                    .font(summaryBodyFont)
                    .foregroundColor(.black)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                Text("•")
                    .font(summaryBodyFont)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(summaryBodyFont)
                    .foregroundColor(.black)
                Text(item)
                    .font(summaryBodyFont)
                    .foregroundColor(.black)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }
    
    private func shareButton(
        for section: ShareSection,
        content: [String],
        index: Int
    ) -> some View {
        Button {
            presentShareComposer(section: section, content: content, index: index)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.primaryGreen)
                .frame(width: 28, height: 28)
                .background(Theme.primaryGreen.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }
    
    private func presentShareComposer(
        section: ShareSection,
        content: [String],
        index: Int
    ) {
        let items = shareItems(for: section, content: content)
        guard items.indices.contains(index) else { return }
        let lockedId = items[index].id
        shareComposerData = ShareComposerData(
            section: section,
            items: items,
            lockedId: lockedId
        )
    }
    
    private func shareItems(
        for section: ShareSection,
        content: [String]
    ) -> [ShareItem] {
        content.enumerated().map { index, text in
            let id: String
            if let lectureId, !lectureId.isEmpty {
                id = "\(lectureId)_\(section.rawValue)_\(index)"
            } else {
                id = "\(section.rawValue)_\(index)"
            }
            return ShareItem(id: id, section: section, text: text, index: index)
        }
    }
}

enum ShareSection: String, Hashable {
    case keyPoints
    case weeklyActions

    var cardTitle: String {
        switch self {
        case .keyPoints:
            return "Key Takeaways"
        case .weeklyActions:
            return "Weekly Actions"
        }
    }
}

struct ShareItem: Identifiable, Hashable {
    let id: String
    let section: ShareSection
    let text: String
    let index: Int
}

struct ShareComposerData: Identifiable {
    let id = UUID()
    let section: ShareSection
    let items: [ShareItem]
    let lockedId: String
}

struct ShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let section: ShareSection
    let items: [ShareItem]
    let lockedId: String
    @State private var selectedIds: Set<String>
    @State private var includeAttribution = false
    @State private var attributionText = ""
    @State private var isShareSheetPresented = false
    @State private var renderedImage: UIImage? = nil

    init(section: ShareSection, items: [ShareItem], lockedId: String) {
        self.section = section
        self.items = items
        self.lockedId = lockedId
        _selectedIds = State(initialValue: [lockedId])
    }

    private var selectedItems: [ShareItem] {
        items
            .filter { selectedIds.contains($0.id) }
            .sorted(by: { $0.index < $1.index })
    }

    private var attributionLine: String? {
        guard includeAttribution else { return nil }
        let trimmed = attributionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard

                    selectionCard
                    attributionCard

                    Button(action: shareImage) {
                        Text("Share")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIds.isEmpty)
                    .opacity(selectedIds.isEmpty ? 0.5 : 1)
                }
                .padding()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $isShareSheetPresented) {
            if let renderedImage {
                ShareSheet(activityItems: [renderedImage])
            }
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected (\(selectedItems.count)/3)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.mutedText)

            ForEach(items) { item in
                Button {
                    toggleSelection(item)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedIds.contains(item.id) ? Theme.primaryGreen : Theme.mutedText)
                        Text("\(item.index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.mutedText)
                        Text(item.text)
                            .font(Theme.bodyFont)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
    }

    private var previewCard: some View {
        ShareCardView(
            section: section,
            selectedItems: selectedItems,
            dateText: nil,
            attribution: attributionLine
        )
        .frame(width: 1080, height: 1080)
        .scaleEffect(previewScale)
        .frame(width: previewSide, height: previewSide)
        .frame(maxWidth: .infinity)
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 4)
    }

    private var previewSide: CGFloat {
        let width = UIScreen.main.bounds.width - 32
        return min(max(width, 240), 420)
    }

    private var previewScale: CGFloat {
        previewSide / 1080
    }

    private var attributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include attribution", isOn: $includeAttribution)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            if includeAttribution {
                TextField("Masjid • Speaker", text: $attributionText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.bodyFont)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
    }

    private func toggleSelection(_ item: ShareItem) {
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else if selectedIds.count < 3 {
            selectedIds.insert(item.id)
        }
    }

    private func shareImage() {
        guard let uiImage = renderShareImage() else { return }
        renderedImage = uiImage
        isShareSheetPresented = true
    }

    private func renderShareImage() -> UIImage? {
        let card = ShareCardView(
            section: section,
            selectedItems: selectedItems,
            dateText: nil,
            attribution: attributionLine
        )
        .frame(width: 1080, height: 1080)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: card)
            renderer.scale = 1
            return renderer.uiImage
        }

        let controller = UIHostingController(rootView: card)
        let size = CGSize(width: 1080, height: 1080)
        guard let view = controller.view else { return nil }
        view.bounds = CGRect(origin: .zero, size: size)
        view.backgroundColor = .clear
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
}

struct ShareCardView: View {
    let section: ShareSection
    let selectedItems: [ShareItem]
    let dateText: String?
    let attribution: String?
    
    private var itemCount: Int {
        max(selectedItems.count, 1)
    }
    
    private var headerFontSize: CGFloat {
        itemCount == 1 ? 56 : 50
    }
    
    private var bodyFontSize: CGFloat {
        switch itemCount {
        case 1:
            return 46
        case 2:
            return 40
        default:
            return 34
        }
    }
    
    private var numberFontSize: CGFloat {
        bodyFontSize - 6
    }

    private var numberColumnWidth: CGFloat {
        max(numberFontSize * 1.1, 30)
    }
    
    private var footerFontSize: CGFloat { 28 }
    private var attributionFontSize: CGFloat { 26 }
    private var contentPadding: CGFloat { 72 }
    private var itemSpacing: CGFloat { 22 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .stroke(Theme.primaryGreen.opacity(0.12), lineWidth: 2)
                )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 28) {
                    Text(section.cardTitle)
                        .font(.system(size: headerFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Theme.primaryGreen, Theme.secondaryGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .center, spacing: itemSpacing) {
                    ForEach(selectedItems.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: numberFontSize, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.primaryGreen.opacity(0.75))
                                .frame(width: numberColumnWidth, alignment: .trailing)
                            Text(selectedItems[index].text)
                                .font(.system(size: bodyFontSize, weight: .regular, design: .serif))
                                .foregroundColor(.black)
                                .lineLimit(3)
                                .lineSpacing(6)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Rectangle()
                        .fill(Theme.primaryGreen.opacity(0.12))
                        .frame(width: 120, height: 1)
                        .padding(.bottom, 6)

                    if let attribution, !attribution.isEmpty {
                        Text(attribution)
                            .font(.system(size: attributionFontSize, weight: .medium, design: .serif))
                            .foregroundColor(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 8) {
                        Image("KhutbahNotesLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                        Text("Khutbah Notes")
                            .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.primaryGreen)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

struct TextSizeToggle: View {
    @Binding var selection: TextSizeOption
    var showsBackground: Bool = true
    
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
            .padding(.vertical, showsBackground ? 6 : 2)
            .background(showsBackground ? Theme.cardBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                Group {
                    if showsBackground {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.primaryGreen.opacity(0.18), lineWidth: 1)
                    }
                }
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

struct SummaryRetryButton: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label("Retry summary", systemImage: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Theme.primaryGreen, Theme.secondaryGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Theme.primaryGreen.opacity(0.18), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry summary")
    }
}

private struct PillSegmentedControl: View {
    let segments: [String]
    @Binding var selection: Int

    private let backgroundColor = Theme.primaryGreen.opacity(0.08)
    private let borderColor = Theme.primaryGreen.opacity(0.16)
    private let activeTextColor = Theme.primaryGreen
    private let inactiveTextColor = Theme.mutedText
    private let font = Font.system(size: 14, weight: .semibold, design: .rounded)

    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(segments.indices, id: \.self) { index in
                Button {
                    guard selection != index else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        selection = index
                    }
                } label: {
                    ZStack {
                        if selection == index {
                            Capsule()
                                .fill(Theme.cardBackground)
                                .matchedGeometryEffect(id: "pill", in: selectionAnimation)
                                .shadow(color: Theme.shadow.opacity(0.6), radius: 4, x: 0, y: 2)
                        }
                        Text(segments[index])
                            .font(font)
                            .foregroundColor(selection == index ? activeTextColor : inactiveTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segments[index])
            }
        }
        .padding(4)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
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
    @State private var showAccountSheet = false
    @State private var showPaywallFromAccount = false

    private var shouldShowUpgrade: Bool {
        (store.userUsage?.plan ?? "free") != "premium"
    }

    private var isPremiumPlan: Bool {
        (store.userUsage?.plan ?? "free") == "premium"
    }

    private var planName: String {
        isPremiumPlan ? "Premium" : "Free"
    }

    var body: some View {
        NavigationView {
            List {
                if shouldShowUpgrade {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Support Khutbah Notes", systemImage: "sparkles")
                        }
                    }
                }

                Section {
                    Button {
                        showAccountSheet = true
                    } label: {
                        Label("Plan: \(planName)", systemImage: isPremiumPlan ? "crown.fill" : "leaf.fill")
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
                    Button {
                        requestAppStoreReview()
                    } label: {
                        Label("Rate Khutbah Notes", systemImage: "star.fill")
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
        .sheet(isPresented: $showAccountSheet, onDismiss: {
            if showPaywallFromAccount {
                showPaywallFromAccount = false
                showPaywall = true
            }
        }) {
            AccountSheetView(onClose: {
                showAccountSheet = false
            }, onUpgrade: {
                showPaywallFromAccount = true
                showAccountSheet = false
            })
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

    private func requestAppStoreReview() {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview()
        }
    }
}

#Preview("Notes") {
    NotesView(
        selectedTab: .constant(0),
        dashboardNavigationDepth: .constant(0)
    )
        .environmentObject(LectureStore(seedMockData: true))
}

#Preview("Lecture Card") {
    LectureCardView(lecture: .mock)
        .environmentObject(LectureStore())
        .padding()
        .background(Theme.background)
}
