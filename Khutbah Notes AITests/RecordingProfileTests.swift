import XCTest
import AVFoundation
@testable import Khutbah_Notes_AI

final class RecordingProfileTests: XCTestCase {
    func testSpeechProfileSettings() {
        let profile = RecordingProfile.speech
        let settings = profile.settings
        
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 44_100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVEncoderBitRateKey] as? Int, 96_000)
        XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(settings[AVEncoderAudioQualityKey] as? Int, AVAudioQuality.high.rawValue)
    }
}
