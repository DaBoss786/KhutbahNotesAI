import Foundation
import Combine
import AVFoundation

/// Handles microphone permissions and audio recording lifecycle.
final class RecordingManager: ObservableObject {
    @Published var isRecording: Bool = false
    
    private var audioRecorder: AVAudioRecorder?
    
    enum RecordingError: Error {
        case permissionDenied
        case failedToStart
    }
    
    func startRecording() throws {
        guard audioRecorder == nil else { return }
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        
        switch session.recordPermission {
        case .granted:
            try beginRecording()
        case .denied:
            throw RecordingError.permissionDenied
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    if granted {
                        do {
                            try self.beginRecording()
                        } catch {
                            print("Failed to start recording after permission granted: \(error)")
                        }
                    } else {
                        print("Microphone permission denied by user.")
                    }
                }
            }
        @unknown default:
            print("Unknown microphone permission status.")
        }
    }
    
    private func beginRecording() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.prepareToRecord()
        
        guard audioRecorder?.record() == true else {
            isRecording = false
            audioRecorder = nil
            throw RecordingError.failedToStart
        }
        
        isRecording = true
    }
    
    func stopRecording() -> URL? {
        guard let recorder = audioRecorder else {
            isRecording = false
            print("No active recording to stop.")
            return nil
        }
        
        recorder.stop()
        isRecording = false
        let recordedURL = recorder.url
        audioRecorder = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        return recordedURL
    }
}
