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

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NotesView()
                    .tabItem {
                        Image(systemName: "book.closed.fill")
                        Text("Notes")
                    }
                    .tag(0)
                
                RecordLectureView()
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
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var store: LectureStore
    @State private var selectedSegment = 0
    
    private let segments = ["All Notes", "Folders"]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }
    
    var body: some View {
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
    
    @ViewBuilder
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                PromoBannerView()
                segmentPicker
                lectureList
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
                NavigationLink {
                    LectureDetailView(lecture: lecture)
                } label: {
                    LectureCardView(lecture: lecture)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PromoBannerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upgrade to Pro")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Unlock unlimited AI summaries and cloud backup for your lectures.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: {}) {
                Text("View Plans")
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
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.mutedText)
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}

struct LectureDetailView: View {
    let lecture: Lecture
    @State private var selectedTab = 0
    
    private let tabs = ["Summary", "Transcript"]
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: lecture.date)
    }
    
    private var durationText: String {
        if let minutes = lecture.durationMinutes {
            return "\(minutes) mins"
        }
        return "Duration pending"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lecture.title)
                    .font(Theme.largeTitleFont)
                    .foregroundColor(.black)
                
                HStack(spacing: 8) {
                    Label(dateText, systemImage: "calendar")
                    Label(durationText, systemImage: "clock")
                    Label(lecture.status.rawValue.capitalized, systemImage: "bolt.horizontal.circle")
                }
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)

                LectureAudioPlayerView(audioPath: lecture.audioPath)
                
                Divider()
                
                Picker("Content", selection: $selectedTab) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        Text(tabs[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                
                if selectedTab == 0 {
                    SummaryView(summary: lecture.summary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript")
                            .font(Theme.titleFont)
                        Text(lecture.transcript ?? "Transcript will appear here once ready.")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Lecture")
        .navigationBarTitleDisplayMode(.inline)
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
    
    var rateLabel: String {
        String(format: "%.2gx", playbackRate)
    }
    
    var canAdjustRate: Bool { canPlay }
    private let missingAudioMessage = "The audio file does not exist or was deleted after 30 days"
    
    private var player: AVPlayer?
    private var endObserver: Any?
    private var currentPath: String?
    private var loadFailed = false
    private var hasAudioPath = false
    
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
        player = nil
        canPlay = false
        isPlaying = false
        statusText = ""
        currentPath = nil
        loadFailed = false
        hasAudioPath = false
    }
    
    private func resetPlayerState() {
        removeEndObserver()
        player?.pause()
        player = nil
        canPlay = false
        isPlaying = false
        loadFailed = false
    }
    
    private func addEndObserver() {
        guard let item = player?.currentItem else { return }
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.statusText = ""
            self.player?.seek(to: .zero)
        }
    }
    
    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

struct SummaryView: View {
    let summary: LectureSummary?
    
    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Summary")
                    .font(Theme.titleFont)
            
            if let summary {
                summarySection(title: "Main Theme", content: [summary.mainTheme])
                summarySection(title: "Key Points", content: summary.keyPoints)
                summarySection(title: "Explicit Ayat or Hadith",
                               content: summary.explicitAyatOrHadith)
                summarySection(title: "Character Traits",
                               content: summary.characterTraits)
                summarySection(title: "Weekly Actions",
                               content: summary.weeklyActions)
            } else {
                Text("AI summary will appear here once processed.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private func summarySection(title: String, content: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
            
            if content.isEmpty {
                Text("None mentioned")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
            } else if content.count == 1 {
                Text(content[0])
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(content, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.mutedText)
                            Text(item)
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Account")) {
                    Label("Profile", systemImage: "person.circle")
                    Label("Subscription", systemImage: "creditcard")
                }
                
                Section(header: Text("App")) {
                    Label("Notifications", systemImage: "bell.badge")
                    Label("Storage", systemImage: "externaldrive")
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
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
