import Foundation
import Combine
import AVFoundation

/// Handles microphone permissions and audio recording lifecycle.
final class RecordingManager: NSObject, ObservableObject {
    static let shared = RecordingManager()

    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var level: Double = 0
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var elapsedTimer: Timer?
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0
    private var lastRecordingURL: URL?
    private var notificationObservers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    private var liveActivityController: Any?
    private let meterInterval: TimeInterval = 0.25
    private let elapsedInterval: TimeInterval = 1
    
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
        lastRecordingURL = nil
        
        let fileURL: URL
        do {
            fileURL = try RecordingStorage.newRecordingURL()
        } catch {
            fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            print("Failed to create persistent recording URL: \(error)")
        }
        
        let profile = RecordingProfile.speech
        
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: profile.settings)
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
        startTimers()
        startLiveActivityIfAvailable(isPaused: false)
    }
    
    func stopRecording() -> URL? {
        guard let recorder = audioRecorder else {
            isRecording = false
            isPaused = false
            if let cachedURL = lastRecordingURL {
                return cachedURL
            }
            print("No active recording to stop.")
            return nil
        }
        
        shouldResumeAfterInterruption = false
        recorder.stop()
        isRecording = false
        isPaused = false
        stopTimers()
        endLiveActivityIfAvailable()
        resetTiming()
        let recordedURL = recorder.url
        lastRecordingURL = recordedURL
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
        elapsedTime = accumulatedTime
        stopTimers()
        startLiveActivityIfAvailable(isPaused: true)
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
            startTimers()
            updateElapsedTime()
            startLiveActivityIfAvailable(isPaused: false)
        } else {
            print("Failed to resume recording.")
        }
    }

    private func configureSession() throws {
        let profile = RecordingProfile.speech
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try? audioSession.setPreferredSampleRate(profile.sampleRate)
        try audioSession.setActive(true)
        setPreferredInput()
    }
    
    private func setPreferredInput() {
        guard let inputs = audioSession.availableInputs else { return }
        if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
            do {
                try audioSession.setPreferredInput(builtIn)
            } catch {
                print("Failed to set preferred microphone: \(error)")
            }
        }
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
        let recordedURL = audioRecorder?.url
        audioRecorder?.stop()
        if let recordedURL {
            lastRecordingURL = recordedURL
        }
        audioRecorder = nil
        shouldResumeAfterInterruption = false
        isRecording = false
        isPaused = false
        stopTimers()
        endLiveActivityIfAvailable()
        resetTiming()
        do {
            try configureSession()
        } catch {
            print("Failed to reconfigure audio session after reset: \(error)")
        }
    }
    
    private func startTimers() {
        stopTimers()
        meterTimer = Timer.scheduledTimer(withTimeInterval: meterInterval, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: elapsedInterval, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }
        if let meterTimer {
            RunLoop.current.add(meterTimer, forMode: .common)
        }
        if let elapsedTimer {
            RunLoop.current.add(elapsedTimer, forMode: .common)
        }
    }

    private func stopTimers() {
        meterTimer?.invalidate()
        meterTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func resetTiming() {
        startDate = nil
        accumulatedTime = 0
        elapsedTime = 0
        level = 0
    }

    private func updateMeters() {
        guard isRecording else { return }
        guard !isPaused else {
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
    
    private func updateElapsedTime() {
        guard isRecording else { return }
        elapsedTime = currentElapsed
    }

    private var currentElapsed: TimeInterval {
        if !isPaused, let startDate {
            return accumulatedTime + Date().timeIntervalSince(startDate)
        }
        return accumulatedTime
    }

    var currentElapsedTime: TimeInterval {
        currentElapsed
    }

    var hasPendingRecording: Bool {
        lastRecordingURL != nil
    }

    func clearLastRecording() {
        lastRecordingURL = nil
    }

    private func startLiveActivityIfAvailable(isPaused: Bool) {
        guard #available(iOS 16.1, *) else { return }
        let elapsed = currentElapsed
        Task { @MainActor in
            if liveActivityController == nil {
                liveActivityController = RecordingLiveActivityController(activityName: RecordingLiveActivityController.defaultActivityName)
            }
            (liveActivityController as? RecordingLiveActivityController)?
                .startOrUpdate(isPaused: isPaused, elapsed: elapsed)
        }
    }

    private func endLiveActivityIfAvailable() {
        guard #available(iOS 16.1, *) else { return }
        let elapsed = currentElapsed
        Task { @MainActor in
            (liveActivityController as? RecordingLiveActivityController)?
                .end(finalElapsed: elapsed)
            liveActivityController = nil
        }
    }
}

extension RecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let isCurrent = recorder == audioRecorder
        if isRecording {
            isRecording = false
            isPaused = false
            stopTimers()
            endLiveActivityIfAvailable()
            resetTiming()
        }
        if !flag {
            print("Audio recorder finished unsuccessfully.")
        }
        if lastRecordingURL == nil {
            lastRecordingURL = recorder.url
        }
        if isCurrent {
            audioRecorder = nil
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard recorder == audioRecorder else { return }
        print("Audio recorder encode error: \(error?.localizedDescription ?? "Unknown error")")
        if isRecording {
            isRecording = false
            isPaused = false
            stopTimers()
            endLiveActivityIfAvailable()
            resetTiming()
        }
        if lastRecordingURL == nil {
            lastRecordingURL = recorder.url
        }
    }
}
