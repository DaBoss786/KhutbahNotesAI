import Foundation
import Combine
import AVFoundation

/// Handles microphone permissions and audio recording lifecycle.
final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var level: Double = 0
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    
    enum RecordingError: Error {
        case permissionDenied
        case failedToStart
    }
    
    override init() {
        super.init()
        addAudioSessionObservers()
    }
    
    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func startRecording() throws {
        guard audioRecorder == nil else { return }
        
        switch audioSession.recordPermission {
        case .granted:
            try beginRecording()
        case .denied:
            throw RecordingError.permissionDenied
        case .undetermined:
            audioSession.requestRecordPermission { [weak self] granted in
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
        try configureSession()
        
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
        audioRecorder?.delegate = self
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
        
        shouldResumeAfterInterruption = false
        recorder.stop()
        isRecording = false
        isPaused = false
        stopMeteringTimer()
        resetTiming()
        let recordedURL = recorder.url
        audioRecorder = nil
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        return recordedURL
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        shouldResumeAfterInterruption = false
        if let startDate {
            accumulatedTime += Date().timeIntervalSince(startDate)
        }
        self.startDate = nil
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        do {
            try configureSession()
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }
        let resumed = audioRecorder?.record() ?? false
        if resumed {
            isPaused = false
            startDate = Date()
        } else {
            print("Failed to resume recording.")
        }
    }

    private func configureSession() throws {
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
    }
    
    private func addAudioSessionObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                self?.handleSessionInterruption(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                self?.handleMediaServicesReset(notification)
            }
        )
    }
    
    private func handleSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            if isRecording, !isPaused {
                pauseRecording()
                shouldResumeAfterInterruption = true
            } else {
                shouldResumeAfterInterruption = false
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), shouldResumeAfterInterruption {
                resumeRecording()
            }
            shouldResumeAfterInterruption = false
        @unknown default:
            shouldResumeAfterInterruption = false
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard isRecording, !isPaused else { return }
        do {
            try configureSession()
        } catch {
            print("Failed to restore audio session after route change: \(error)")
        }
    }
    
    private func handleMediaServicesReset(_ notification: Notification) {
        guard isRecording else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        shouldResumeAfterInterruption = false
        isRecording = false
        isPaused = false
        stopMeteringTimer()
        resetTiming()
        do {
            try configureSession()
        } catch {
            print("Failed to reconfigure audio session after reset: \(error)")
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

extension RecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder == audioRecorder else { return }
        if isRecording {
            isRecording = false
            isPaused = false
            stopMeteringTimer()
            resetTiming()
        }
        if !flag {
            print("Audio recorder finished unsuccessfully.")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard recorder == audioRecorder else { return }
        print("Audio recorder encode error: \(error?.localizedDescription ?? "Unknown error")")
        if isRecording {
            isRecording = false
            isPaused = false
            stopMeteringTimer()
            resetTiming()
        }
    }
}
