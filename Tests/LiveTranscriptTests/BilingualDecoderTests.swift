import AVFoundation
import Foundation
import Testing
@testable import LiveTranscript

@Test func mapsEnglishAndChineseTokensToTheDisplayedCharacters() throws {
    let json = #"{"text":"你好， final report.","tokens":[" 你"," 好"," ，"," final"," report","."],"timestamps":[0.4,0.5,0.6,0.9,1.1,1.25],"start_time":2.0}"#
    let snapshot = try JSONDecoder().decode(BilingualSnapshot.self, from: Data(json.utf8))
    let characters = snapshot.characterTiming(startedAt: 3)
    #expect(characters.map(\.value).joined() == "你好finalreport")
    #expect(characters[2].index == 4)
    #expect(abs(characters[2].start - 3.9) < 0.001)
}

private let environment = ProcessInfo.processInfo.environment
private let runtimeFixtureAvailable = environment["HUITING_ASR_TEST_ASSETS"] != nil
    && environment["HUITING_ASR_TEST_WAVS"] != nil

@Test(.enabled(if: runtimeFixtureAvailable, "Requires the bundled model and Chinese and English test WAV files"))
func recognizesChineseAndEnglishOnBothSourcesWithoutChangingSettings() throws {
    let modelRoot = try #require(environment["HUITING_ASR_TEST_ASSETS"])
    let waves = URL(fileURLWithPath: try #require(environment["HUITING_ASR_TEST_WAVS"]))
    let decoder = try BilingualDecoder(assets: SpeechAssets(root: URL(fileURLWithPath: modelRoot)))
    let chinese = try samples(in: waves.appending(path: "mandarin.wav"))
    let english = try samples(in: waves.appending(path: "english.wav"))
    let pause = [Float](repeating: 0, count: 24_000)
    let microphone = chinese + pause + english
    let application = english + pause + chinese

    var updates: [TranscriptUpdate] = []
    for start in stride(from: 0, to: microphone.count, by: 1_600) {
        let end = min(microphone.count, start + 1_600)
        updates += try decoder.consume(.init(
            source: .microphone, startSample: Int64(start), samples: Array(microphone[start..<end])
        ))
        updates += try decoder.consume(.init(
            source: .application, startSample: Int64(start), samples: Array(application[start..<end])
        ))
    }
    updates += try decoder.finish()

    for source: TranscriptSource in [.application, .microphone] {
        let track = updates.filter { $0.source == source }
        let final = track.filter(\.isFinal)
        let text = final.map(\.text).joined(separator: " ")
        #expect(text.contains("下午三点开会"))
        #expect(text.lowercased().contains("the release is ready"))
        #expect(track.contains { !$0.isFinal && !$0.text.isEmpty })
        #expect(final.count >= 2)
        #expect(final.map(\.offset) == final.map(\.offset).sorted())
    }

    // A pause finishes both streams; the next capture interval reuses the model.
    let resumedAt = Int64(microphone.count + 80_000)
    var resumed: [TranscriptUpdate] = []
    for start in stride(from: 0, to: english.count, by: 1_600) {
        let end = min(english.count, start + 1_600)
        resumed += try decoder.consume(.init(
            source: .application, startSample: resumedAt + Int64(start), samples: Array(english[start..<end])
        ))
    }
    resumed += try decoder.finish()
    #expect(resumed.filter(\.isFinal).map(\.text).joined(separator: " ").lowercased().contains("the release is ready"))
    #expect(resumed.allSatisfy { $0.source == .application && $0.offset >= Double(resumedAt) / 16_000 })
}

private func samples(in file: URL) throws -> [Float] {
    let input = try AVAudioFile(forReading: file)
    #expect(input.processingFormat.sampleRate == Double(BilingualDecoder.sampleRate))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
    try input.read(into: buffer)
    let data = try #require(buffer.floatChannelData?.pointee)
    return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
}
