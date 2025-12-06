import SwiftUI
import AVFoundation

struct RecordLectureView: View {
    @EnvironmentObject var store: LectureStore
    @StateObject private var recordingManager = RecordingManager()
    @State private var showTitleSheet = false
    @State private var titleText = ""
    @State private var lastRecordingURL: URL? = nil
    
    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            VStack(spacing: 8) {
                Text("Record a Khutbah")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Tap record to capture the sermon. You can name it afterwards.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            
            Spacer()
            
            Button(action: recordingManager.isRecording ? stopRecordingTapped : startRecordingTapped) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(recordingManager.isRecording ? Color.red.opacity(0.85) : Color.red)
                            .frame(width: 120, height: 120)
                            .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 8)
                        
                        Image(systemName: recordingManager.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text(recordingManager.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding()
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showTitleSheet) {
            namingSheet
        }
    }
    
    private var namingSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name your lecture")
                .font(.title2.bold())
            
            TextField("Lecture title", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            
            Text("You can change this later.")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: {
                    guard let url = lastRecordingURL else {
                        print("No recording URL available when saving lecture.")
                        showTitleSheet = false
                        return
                    }
                    
                    let finalTitle = titleText.isEmpty ? defaultTitle() : titleText
                    store.createLecture(withTitle: finalTitle, recordingURL: url)
                    showTitleSheet = false
                }) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    guard let url = lastRecordingURL else {
                        print("No recording URL available when skipping title.")
                        showTitleSheet = false
                        return
                    }
                    
                    let finalTitle = defaultTitle()
                    store.createLecture(withTitle: finalTitle, recordingURL: url)
                    showTitleSheet = false
                }) {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
    
    private func startRecordingTapped() {
        do {
            try recordingManager.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecordingTapped() {
        let url = recordingManager.stopRecording()
        guard let url = url else {
            print("No recording URL available")
            return
        }
        
        lastRecordingURL = url
        titleText = defaultTitle()
        
        showTitleSheet = true
    }
    
    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Khutbah – \(formatter.string(from: Date()))"
    }
}

struct RecordLectureView_Previews: PreviewProvider {
    static var previews: some View {
        RecordLectureView()
            .environmentObject(LectureStore())
    }
}
