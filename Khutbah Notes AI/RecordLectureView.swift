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
                Button(action: saveLecture) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: skipLecture) {
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
        titleText = makeDefaultTitle()
        
        showTitleSheet = true
    }
    
    private func saveLecture() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = trimmed.isEmpty ? makeDefaultTitle() : trimmed
        createLecture(with: defaultTitle)
    }
    
    private func skipLecture() {
        createLecture(with: makeDefaultTitle())
    }
    
    private func createLecture(with title: String) {
        let newLecture = Lecture(
            id: UUID().uuidString,
            title: title,
            date: Date(),
            durationMinutes: nil,
            isFavorite: false,
            status: .processing,
            transcript: nil,
            summary: nil
        )
        
        store.addLecture(newLecture)
        
        if let url = lastRecordingURL {
            store.attachRecordingURL(url, to: newLecture.id)
        }
        
        showTitleSheet = false
    }
    
    private func makeDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Khutbah – \(formatter.string(from: Date()))"
    }
}

struct RecordLectureView_Previews: PreviewProvider {
    static var previews: some View {
        RecordLectureView()
            .environmentObject(LectureStore.mockStoreWithSampleData())
    }
}
