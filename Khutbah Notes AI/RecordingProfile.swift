import AVFoundation

struct RecordingProfile: Equatable {
    let sampleRate: Double
    let bitRate: Int
    let channels: Int
    let formatId: AudioFormatID
    let quality: AVAudioQuality
    
    static let speech = RecordingProfile(
        sampleRate: 44_100,
        bitRate: 96_000,
        channels: 1,
        formatId: kAudioFormatMPEG4AAC,
        quality: .high
    )
    
    var settings: [String: Any] {
        [
            AVFormatIDKey: formatId,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: quality.rawValue
        ]
    }
}
