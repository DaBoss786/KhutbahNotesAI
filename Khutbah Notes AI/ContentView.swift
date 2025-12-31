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
    @State private var dashboardNavigationDepth = 0
    @State private var pendingRecordingRouteAction: RecordingRouteAction? = nil
    @AppStorage("hasSavedRecording") private var hasSavedRecording = false
    @AppStorage(RecordingUserDefaultsKeys.controlAction, store: RecordingDefaults.shared) private var pendingControlActionRaw = ""
    @AppStorage(RecordingUserDefaultsKeys.routeAction, store: RecordingDefaults.shared) private var pendingRouteActionRaw = ""
    
    private var shouldShowRecordPrompt: Bool {
        !hasSavedRecording && selectedTab == 0 && dashboardNavigationDepth == 0
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NotesView(
                    selectedTab: $selectedTab,
                    dashboardNavigationDepth: $dashboardNavigationDepth
                )
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
            
            if shouldShowRecordPrompt {
                DashboardRecordPrompt()
            }
            
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
        .onAppear {
            handlePendingActions()
        }
        .onChange(of: pendingControlActionRaw) { _ in
            handlePendingControlAction()
        }
        .onChange(of: pendingRouteActionRaw) { _ in
            handlePendingRouteAction()
        }
    }

    private func handlePendingActions() {
        handlePendingControlAction()
        handlePendingRouteAction()
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
}

struct NotesView: View {
    @EnvironmentObject var store: LectureStore
    @Binding var selectedTab: Int
    @Binding var dashboardNavigationDepth: Int
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
    @State private var showAccountSheet = false
    @State private var showPaywallFromAccount = false
    @State private var searchQuery = ""
    @State private var activeSearchQuery = ""
    @State private var showSearchResults = false
    
    private let segments = ["All Notes", "Folders"]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }

    private var isPremiumPlan: Bool {
        (store.userUsage?.plan ?? "free") == "premium"
    }

    private var planName: String {
        isPremiumPlan ? "Premium" : "Free"
    }

    private var monthlyMinutesRemaining: Int {
        max(0, store.userUsage?.minutesRemaining ?? 0)
    }

    private var freeLifetimeMinutesRemaining: Int {
        if let remaining = store.userUsage?.freeLifetimeMinutesRemaining {
            return max(0, remaining)
        }
        let used = store.userUsage?.freeLifetimeMinutesUsed ?? 0
        return max(0, 60 - used)
    }

    private var userIdText: String {
        store.userId ?? "Not available"
    }

    private var canCopyUserId: Bool {
        store.userId != nil
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
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
        .sheet(isPresented: $showAccountSheet, onDismiss: {
            if showPaywallFromAccount {
                showPaywallFromAccount = false
                showPaywall = true
            }
        }) {
            accountSheet
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
                if (store.userUsage?.plan ?? "free") != "premium" {
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
                Button {
                    showAccountSheet = true
                } label: {
                    Image(systemName: "person.crop.circle")
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
                .accessibilityLabel("Account and plan")
            }
            Text("As-salamu alaikum")
                .font(.subheadline)
                .foregroundColor(Theme.mutedText)
        }
    }

    private var accountSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Account")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showAccountSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.mutedText)
                        .padding(8)
                        .background(Theme.cardBackground)
                        .clipShape(Circle())
                        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close account sheet")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Current plan")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                HStack(alignment: .center, spacing: 12) {
                    Text(planName)
                        .font(.title2.bold())
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: isPremiumPlan ? "crown.fill" : "leaf.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.primaryGreen)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 10) {
                Text(isPremiumPlan ? "Monthly minutes remaining" : "Lifetime minutes remaining")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                Text("\(isPremiumPlan ? monthlyMinutesRemaining : freeLifetimeMinutesRemaining) min")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryGreen)
                if !isPremiumPlan {
                    Text("Free plan includes 60 lifetime minutes.")
                        .font(.footnote)
                        .foregroundColor(Theme.mutedText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            if !isPremiumPlan {
                Button {
                    showPaywallFromAccount = true
                    showAccountSheet = false
                } label: {
                    Text("Upgrade")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.primaryGreen)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 8, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("UID")
                    .font(.caption)
                    .foregroundColor(Theme.mutedText)
                HStack(alignment: .top, spacing: 12) {
                    Text(userIdText)
                        .font(.footnote)
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        if let userId = store.userId {
                            UIPasteboard.general.string = userId
                        }
                    } label: {
                        Text("Copy")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.primaryGreen.opacity(0.12))
                            .foregroundColor(Theme.primaryGreen)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCopyUserId)
                    .opacity(canCopyUserId ? 1 : 0.5)
                    .accessibilityLabel("Copy UID")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(18)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 5)

            Spacer()
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.mutedText)
            TextField("Search saved summaries", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
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
        .accessibilityLabel("Search summaries")
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

    private func performSearch() {
        let trimmed = trimmedSearchQuery
        guard !trimmed.isEmpty else { return }
        activeSearchQuery = trimmed
        showSearchResults = true
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
    @State private var shareItems: [Any]? = nil
    @State private var isShareSheetPresented = false
    @State private var copyBannerMessage: String? = nil
    @State private var summaryRetryNow = Date()
    private let summaryRetryTimer =
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @AppStorage("didRequestDemoReview") private var didRequestDemoReview = false
    @AppStorage("realSummaryReviewCountedLectureIDs") private var realSummaryReviewCountedLectureIDs = StoredLectureIDSet()
    @AppStorage("didRequestRealSummaryReview") private var didRequestRealSummaryReview = false
    
    private let tabs = ["Summary", "Transcript"]
    private let failureMessage =
        "Transcription failed. Try recording in a quieter space or closer to the speaker."
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
                Text("Transcription Failed")
                    .font(Theme.titleFont)
                    .foregroundColor(.black)
            }

            Text(failureMessage)
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
                } else {
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
                    
                    if !isTranscriptionFailed {
                        Picker("Content", selection: $selectedContentTab) {
                            ForEach(0..<tabs.count, id: \.self) { index in
                                Text(tabs[index]).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if isTranscriptionFailed {
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
                    } else {
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
        .onReceive(summaryRetryTimer) { date in
            summaryRetryNow = date
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
                    VStack(alignment: sectionAlignment, spacing: 18) {
                        summarySection(title: "Main Theme", content: [summary.mainTheme])
                        summarySection(title: "Key Points",
                                       content: summary.keyPoints,
                                       showsDividers: true,
                                       shareSection: .keyPoints)
                        summarySection(title: "Explicit Ayat or Hadith",
                                       content: summary.explicitAyatOrHadith,
                                       hideWhenEmpty: true,
                                       showsDividers: true)
                        summarySection(title: "Weekly Actions",
                                       content: summary.weeklyActions,
                                       showsDividers: true,
                                       shareSection: .weeklyActions)
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
        shareSection: ShareSection? = nil
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
                    
                    if content.isEmpty {
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
            return "Takeaways"
        case .weeklyActions:
            return "This Week"
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
            .background(Theme.background.ignoresSafeArea())
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
        itemCount == 1 ? 72 : 64
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

            VStack {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 28) {
                    Text(section.cardTitle)
                        .font(.system(size: headerFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 20)
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
                            (Text("\(index + 1). ")
                                .font(.system(size: numberFontSize, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.primaryGreen)
                             + Text(selectedItems[index].text)
                                .font(.system(size: bodyFontSize, weight: .regular, design: .rounded))
                                .foregroundColor(.black)
                            )
                            .lineLimit(3)
                            .lineSpacing(6)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    if let attribution, !attribution.isEmpty {
                        Text(attribution)
                            .font(.system(size: attributionFontSize, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Text("Khutbah Notes")
                        .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryGreen)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }
            .padding(contentPadding)
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
