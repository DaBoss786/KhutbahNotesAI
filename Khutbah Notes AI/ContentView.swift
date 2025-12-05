//
//  ContentView.swift
//  Khutbah Notes AI
//
//  Created by Abbas Anwar on 12/4/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
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
    @State private var selectedSegment = 0
    
    private let segments = ["All Notes", "Folders"]
    private let lectures: [Lecture] = [
        Lecture(title: "Tafseer of Surah Al-Kahf", dateLabel: "Today", duration: "45 mins"),
        Lecture(title: "Understanding Taqwa", dateLabel: "Yesterday", duration: "32 mins"),
        Lecture(title: "Mercy and Patience", dateLabel: "Last Friday", duration: "28 mins")
    ]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }
    
    var body: some View {
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
            ForEach(lectures) { lecture in
                LectureCardView(lecture: lecture)
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.primaryGreen, Theme.secondaryGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(18)
        .shadow(color: Theme.shadow, radius: 10, x: 0, y: 6)
    }
}

struct Lecture: Identifiable {
    let id = UUID()
    let title: String
    let dateLabel: String
    let duration: String
}

struct LectureCardView: View {
    let lecture: Lecture
    
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
                    Text(lecture.dateLabel)
                    Text("•")
                    Text(lecture.duration)
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

struct RecordLectureView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Theme.primaryGreen)
            Text("Record a new khutbah")
                .font(Theme.titleFont)
                .foregroundColor(.black)
            Text("Tap the microphone to start a new recording and keep your notes organized.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
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
