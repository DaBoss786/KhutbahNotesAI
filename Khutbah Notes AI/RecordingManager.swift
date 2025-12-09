import Foundation
import Combine
import AVFoundation

/// Handles microphone permissions and audio recording lifecycle.
final class RecordingManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var level: Double = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0
    
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
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        guard audioRecorder?.record() == true else {
            isRecording = false
            audioRecorder = nil
            throw RecordingError.failedToStart
        }
        
        isRecording = true
        isPaused = false
        level = 0
        startDate = Date()
        elapsedTime = 0
        accumulatedTime = 0
        startMeteringTimer()
    }
    
    func stopRecording() -> URL? {
        guard let recorder = audioRecorder else {
            isRecording = false
            print("No active recording to stop.")
            return nil
        }
        
        recorder.stop()
        isRecording = false
        isPaused = false
        stopMeteringTimer()
        resetTiming()
        let recordedURL = recorder.url
        audioRecorder = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        return recordedURL
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        if let startDate {
            accumulatedTime += Date().timeIntervalSince(startDate)
        }
        self.startDate = nil
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        let resumed = audioRecorder?.record() ?? false
        if resumed {
            isPaused = false
            startDate = Date()
        }
    }

    private func startMeteringTimer() {
        stopMeteringTimer()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.updateMetersAndTime()
        }
        RunLoop.current.add(meterTimer!, forMode: .common)
    }

    private func stopMeteringTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func resetTiming() {
        startDate = nil
        accumulatedTime = 0
        elapsedTime = 0
        level = 0
    }

    private func updateMetersAndTime() {
        guard isRecording else { return }
        if !isPaused, let startDate {
            elapsedTime = accumulatedTime + Date().timeIntervalSince(startDate)
        } else if isPaused {
            level = 0
            return
        }

        audioRecorder?.updateMeters()
        guard let power = audioRecorder?.averagePower(forChannel: 0) else {
            level = 0
            return
        }

        // Convert decibel scale (-160...0) to 0...1 range for UI.
        let minDb: Float = -80
        let clamped = max(minDb, power)
        let normalized = pow(10, clamped / 20)
        level = Double(normalized)
    }
}
