import SwiftUI
import AVFoundation

struct RecordLectureView: View {
    @Binding var selectedTab: Int
    @Binding var pendingRouteAction: RecordingRouteAction?
    var onShowToast: ((String, String?, (() -> Void)?) -> Void)? = nil
    var onShowPaywall: (() -> Void)? = nil
    
    @EnvironmentObject var store: LectureStore
    @StateObject private var recordingManager = RecordingManager.shared
    @State private var showTitleSheet = false
    @State private var titleText = ""
    @State private var animatePulse = false
    @State private var blinkDot = false
    @State private var showDiscardAlert = false
    @State private var didShowLimitWarning = false
    @State private var didAutoStopForLimit = false
    @State private var limitReachedMessage: String? = nil
    @AppStorage("hasSavedRecording") private var hasSavedRecording = false
    
    private enum RecordingLimitKind {
        case freeLifetime
        case premiumMonthly
        case perRecording
    }
    
    private struct RecordingLimit {
        let minutes: Int
        let kind: RecordingLimitKind
    }
    
    private let warningThresholdSeconds: TimeInterval = 180
    private let freeLifetimeCapMinutes = 60
    private let premiumMonthlyCapMinutes = 500
    private let perRecordingCapMinutes = 70
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Color.white],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(alignment: .center, spacing: 24) {
                header
                
                Spacer(minLength: 12)
                
                VStack(spacing: 18) {
                    usageCard
                    blockedBanner
                    
                    if recordingManager.isRecording {
                        recordingBadge
                        limitWarningView
                    }
                    
                    recordButtonStack
                    
                    if recordingManager.isRecording {
                        timerView
                        waveformView
                        controlRow
                    } else {
                        tapHint
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showTitleSheet) {
            if #available(iOS 16.0, *) {
                namingSheet
                    .presentationDetents([.medium, .large])
            } else {
                namingSheet
            }
        }
        .onAppear {
            if recordingManager.isRecording { startPulse() }
            handlePendingRouteAction()
        }
        .onChange(of: recordingManager.isRecording) { isRecording in
            if isRecording {
                startPulse()
            } else {
                stopPulse()
                resetLimitState()
            }
        }
        .onChange(of: recordingManager.elapsedTime) { _ in
            handleLimitTick()
        }
        .onChange(of: pendingRouteAction) { _ in
            handlePendingRouteAction()
        }
        .alert("Discard recording?", isPresented: $showDiscardAlert) {
            Button("Delete", role: .destructive) {
                discardRecording()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the current khutbah recording.")
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
            
            if let limitReachedMessage {
                Text(limitReachedMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("Save to start transcription.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Button(action: saveRecordingTapped) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                if recordingManager.isPaused && limitReachedMessage == nil {
                    Button(action: resumeRecordingTapped) {
                        Text("Resume Recording")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(role: .destructive, action: { showDiscardAlert = true }) {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
    }
    
    private func startRecordingTapped() {
        guard let limit = activeRecordingLimit else {
            onShowToast?("Fetching usage... Try again in a moment.", nil, nil)
            return
        }
        if limit.minutes <= 0 {
            if limit.kind == .freeLifetime {
                onShowToast?(
                    limitReachedStartMessage(for: limit.kind),
                    "Upgrade Now",
                    { onShowPaywall?() }
                )
            } else {
                onShowToast?(limitReachedStartMessage(for: limit.kind), nil, nil)
            }
            return
        }
        resetLimitState()
        do {
            try recordingManager.startRecording()
            titleText = defaultTitle()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func finishRecordingTapped() {
        guard recordingManager.isRecording else { return }
        recordingManager.pauseRecording()
        titleText = titleText.isEmpty ? defaultTitle() : titleText
        showTitleSheet = true
    }
    
    private func saveRecordingTapped() {
        guard let url = recordingManager.stopRecording() else {
            print("No recording URL available")
            showTitleSheet = false
            return
        }
        
        let finalTitle = titleText.isEmpty ? defaultTitle() : titleText
        var createdLectureId: String?
        func handleUploadError(_ message: String) {
            guard let lectureId = createdLectureId else {
                onShowToast?(message, nil, nil)
                return
            }
            onShowToast?(message, "Retry") {
                store.retryLectureUpload(
                    lectureId: lectureId,
                    onError: handleUploadError
                )
            }
        }
        createdLectureId = store.createLecture(
            withTitle: finalTitle,
            recordingURL: url,
            onError: handleUploadError
        )
        
        recordingManager.clearLastRecording()
        hasSavedRecording = true
        showTitleSheet = false
        titleText = ""
        onShowToast?(
            "Audio saved. Transcription and summary will be available in a few minutes.",
            nil,
            nil
        )
        selectedTab = 0
    }
    
    private func resumeRecordingTapped() {
        showTitleSheet = false
        if recordingManager.isPaused {
            recordingManager.resumeRecording()
        }
    }
    
    private func discardRecording() {
        let url = recordingManager.stopRecording()
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
        recordingManager.clearLastRecording()
        showTitleSheet = false
        titleText = ""
    }
    
    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Khutbah - \(formatter.string(from: Date()))"
    }

    private var activeRecordingLimit: RecordingLimit? {
        guard let usage = store.userUsage else { return nil }
        let plan = usage.plan == "premium" ? "premium" : "free"
        let planRemaining = max(0, usage.minutesRemaining)
        if plan == "free" {
            return RecordingLimit(minutes: planRemaining, kind: .freeLifetime)
        }

        if planRemaining <= perRecordingCapMinutes {
            return RecordingLimit(minutes: planRemaining, kind: .premiumMonthly)
        }
        return RecordingLimit(minutes: perRecordingCapMinutes, kind: .perRecording)
    }

    private func remainingSeconds(for limit: RecordingLimit) -> TimeInterval {
        max(0, (TimeInterval(limit.minutes) * 60) - recordingManager.elapsedTime)
    }

    private func limitLabel(for kind: RecordingLimitKind) -> String {
        switch kind {
        case .freeLifetime:
            return "free plan limit"
        case .premiumMonthly:
            return "monthly limit"
        case .perRecording:
            return "per recording limit"
        }
    }
    
    private func limitLabelDisplay(for kind: RecordingLimitKind) -> String {
        switch kind {
        case .freeLifetime:
            return "Free plan limit"
        case .premiumMonthly:
            return "Monthly limit"
        case .perRecording:
            return "Per recording limit"
        }
    }

    private func limitReachedStartMessage(for kind: RecordingLimitKind) -> String {
        switch kind {
        case .freeLifetime:
            return "You have reached the \(freeLifetimeCapMinutes)-minute free plan limit. Upgrade to keep recording."
        case .premiumMonthly:
            return "You have reached your \(premiumMonthlyCapMinutes)-minute monthly limit."
        case .perRecording:
            return "This recording has reached the \(perRecordingCapMinutes)-minute limit."
        }
    }

    private func limitReachedSheetMessage(for kind: RecordingLimitKind) -> String {
        switch kind {
        case .freeLifetime:
            return "Free plan limit reached. Save to process this recording."
        case .premiumMonthly:
            return "Monthly limit reached. Save to process this recording."
        case .perRecording:
            return "Per recording limit reached. Save to process this recording."
        }
    }

    private func formattedRemaining(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = [.pad]
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: seconds) ?? "00:00"
    }

    private func handleLimitTick() {
        guard recordingManager.isRecording else { return }
        guard let limit = activeRecordingLimit else { return }

        let remaining = remainingSeconds(for: limit)
        if remaining <= warningThresholdSeconds, remaining > 0, !didShowLimitWarning {
            didShowLimitWarning = true
            onShowToast?(
                "\(formattedRemaining(remaining)) remaining before you hit your \(limitLabel(for: limit.kind)).",
                nil,
                nil
            )
        }

        if remaining <= 0, !didAutoStopForLimit {
            didAutoStopForLimit = true
            limitReachedMessage = limitReachedSheetMessage(for: limit.kind)
            finishRecordingTapped()
            onShowToast?(
                "Recording stopped at your \(limitLabel(for: limit.kind)).",
                nil,
                nil
            )
        }
    }

    private func resetLimitState() {
        didShowLimitWarning = false
        didAutoStopForLimit = false
        limitReachedMessage = nil
    }

    private func handlePendingRouteAction() {
        guard let action = pendingRouteAction else { return }
        defer { pendingRouteAction = nil }
        switch action {
        case .openRecording:
            selectedTab = 1
        case .showSaveCard:
            selectedTab = 1
            guard recordingManager.isRecording || recordingManager.isPaused || recordingManager.hasPendingRecording else { return }
            titleText = titleText.isEmpty ? defaultTitle() : titleText
            showTitleSheet = true
        }
    }
    
    private func startPulse() {
        animatePulse = false
        blinkDot = false
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            animatePulse = true
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            blinkDot = true
        }
    }
    
    private func stopPulse() {
        animatePulse = false
        blinkDot = false
    }
    
    private var tapHint: some View {
        Text("Tap here to record")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }
    
    private var usageCard: some View {
        let remaining = store.userUsage?.minutesRemaining
        let plan = store.userUsage?.plan ?? "free"
        let isFree = plan == "free"
        let used = isFree ? (store.userUsage?.freeLifetimeMinutesUsed ?? 0) : 0
        let cap = isFree ? freeLifetimeCapMinutes : 0
        let percent = cap > 0 ? min(1.0, Double(used) / Double(cap)) : 0
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan • \(plan.capitalized)")
                        .font(.subheadline.weight(.semibold))
                    if isFree {
                        if let remaining {
                            Text("\(used) / \(cap) minutes used • \(remaining) remaining")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Fetching usage…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("\(perRecordingCapMinutes)-minute max per audio recording.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            
            if isFree {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray6))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: width * percent, height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            if isFree {
                Text("Upgrade for additional recording time.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Tap to upgrade")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.85))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture {
            if isFree {
                onShowPaywall?()
            }
        }
    }
    
    private var blockedLecture: Lecture? {
        store.lectures.first { $0.status == .blockedQuota }
    }
    
    private var blockedBanner: some View {
        guard let lecture = blockedLecture else { return AnyView(EmptyView()) }
        let message: String
        switch lecture.quotaReason {
        case "per_file_cap":
            message = "Blocked: exceeds \(perRecordingCapMinutes)-minute per khutbah limit."
        case "free_lifetime_exceeded":
            message = "Blocked: free plan reached \(freeLifetimeCapMinutes)-minute total."
        case "premium_monthly_exceeded":
            message = "Blocked: premium monthly \(premiumMonthlyCapMinutes)-minute limit reached."
        default:
            message = "Recording blocked due to quota."
        }
        
        return AnyView(
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quota limit hit")
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.12))
            .cornerRadius(12)
            .padding(.horizontal, 24)
        )
    }
}

private extension RecordLectureView {
    var header: some View {
        VStack(spacing: 8) {
            Text("Record a Khutbah")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("Tap record to capture the khutbah. You can name it afterwards.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
    
    var recordButtonStack: some View {
        Button(action: recordingManager.isRecording ? finishRecordingTapped : startRecordingTapped) {
            pulsingRecordButton
        }
        .buttonStyle(.plain)
    }
    
    var pulsingRecordButton: some View {
        ZStack {
            if recordingManager.isRecording {
                Circle()
                    .fill(Theme.secondaryGreen.opacity(0.22))
                    .frame(width: 190, height: 190)
                    .scaleEffect(animatePulse ? 1.06 : 0.92)
                    .opacity(animatePulse ? 0.9 : 0.45)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: animatePulse)
            }
            
            Circle()
                .fill(Color.red)
                .frame(width: 140, height: 140)
                .shadow(color: Color.red.opacity(0.25), radius: 18, x: 0, y: 10)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.white)
                )
        }
        .accessibilityLabel(recordingManager.isRecording ? "Stop recording" : "Start recording")
    }
    
    var helperText: some View {
        Text("Capture the khutbah in high quality. You can pause anytime, and we'll help you name and summarize it afterwards.")
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
    
    var recordingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(blinkDot ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blinkDot)
            Text("Recording...")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.primaryGreen)
                .textCase(.uppercase)
        }
    }
    
    @ViewBuilder
    var limitWarningView: some View {
        if recordingManager.isRecording, let limit = activeRecordingLimit {
            let remaining = remainingSeconds(for: limit)
            if remaining <= warningThresholdSeconds, remaining > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                    Text("\(formattedRemaining(remaining)) remaining • \(limitLabelDisplay(for: limit.kind))")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(12)
            }
        }
    }
    
    var timerView: some View {
        Text(formattedElapsed)
            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(.primary)
    }
    
    var waveformView: some View {
        RecordingWaveformView(level: recordingManager.level)
            .frame(height: 44)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }
    
    var controlRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Button(action: recordingManager.isPaused ? recordingManager.resumeRecording : recordingManager.pauseRecording) {
                    ZStack {
                        Circle()
                            .fill(Theme.secondaryGreen.opacity(0.16))
                            .frame(width: 62, height: 62)
                        Image(systemName: recordingManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.primaryGreen)
                    }
                }
                .buttonStyle(.plain)
                .disabled(limitReachedMessage != nil)
                .opacity(limitReachedMessage == nil ? 1 : 0.4)
                
                Button(action: finishRecordingTapped) {
                    Text("Stop Recording")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(16)
                        .shadow(color: Color.red.opacity(0.22), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    var formattedElapsed: String {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = [.pad]
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: recordingManager.elapsedTime) ?? "00:00"
    }
}

struct RecordingWaveformView: View {
    let level: Double
    
    // Slightly varied pattern to make the line feel alive without randomness each frame.
    private let pattern: [Double] = [0.35, 0.6, 0.9, 0.55, 0.75, 1, 0.72, 0.48, 0.3]
    
    var body: some View {
        let mirrored = pattern + pattern.dropLast().reversed()
        let heightScale = max(8, level * 90)
        
        return HStack(alignment: .center, spacing: 5) {
            ForEach(Array(mirrored.enumerated()), id: \.offset) { item in
                Capsule()
                    .fill(Theme.secondaryGreen)
                    .frame(width: 4, height: max(6, CGFloat(item.element) * CGFloat(heightScale)))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }
}

struct ToastView: View {
    let message: String
    let actionTitle: String
    var onAction: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Button(action: { onAction?() }) {
                Text(actionTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryGreen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.primaryGreen.opacity(0.95))
                .shadow(color: Theme.primaryGreen.opacity(0.25), radius: 10, x: 0, y: 8)
        )
        .padding(.horizontal, 24)
    }
}

struct RecordLectureView_Previews: PreviewProvider {
    static var previews: some View {
        RecordLectureView(selectedTab: .constant(1), pendingRouteAction: .constant(nil))
            .environmentObject(LectureStore())
    }
}
