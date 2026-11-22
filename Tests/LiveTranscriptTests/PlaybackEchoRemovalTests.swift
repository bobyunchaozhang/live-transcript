import AVFoundation
import CoreMedia
import EchoDSP
import Foundation
import Testing
@testable import LiveTranscript

@Test func removesDelayedPlaybackWhileRetainingAnOverlappingLocalVoice() throws {
    let rate = Int(EchoSampleRate)
    let total = rate * 7
    var farGenerator = SpeechLikeSignal(seed: 42, fundamental: 164)
    var localGenerator = SpeechLikeSignal(seed: 87, fundamental: 113)
    let render = (0..<total).map { farGenerator.sample($0) }
    let local = (0..<total).map { index in
        (rate * 3 ..< rate * 5).contains(index) ? localGenerator.sample(index) : 0
    }
    let echo = (0..<total).map { index -> Int16 in
        let direct = index >= 190 ? Double(render[index - 190]) * 0.70 : 0
        let reflection = index >= 511 ? Double(render[index - 511]) * 0.21 : 0
        return Int16(clamping: Int(direct + reflection))
    }
    let microphone = zip(echo, local).map { Int16(clamping: Int($0) + Int($1)) }
    let cleaned = try filter(microphone: microphone, render: render)

    #expect(cleaned.count == total)
    let farOnly = (rate * 2)..<(rate * 3)
    let doubleTalk = (rate * 3 + 1_600)..<(rate * 5)
    #expect(power(cleaned, farOnly) < power(echo, farOnly) * 0.08)

    let localPower = power(local, doubleTalk)
    let localGain = Double(dot(cleaned, local, doubleTalk)) / localPower
    #expect(localGain > 0.55)
    let echoProjection = Double(dot(cleaned, echo, doubleTalk))
        - localGain * Double(dot(local, echo, doubleTalk))
    #expect(abs(echoProjection / power(echo, doubleTalk)) < 0.25)
}

@Test func keepsMicrophoneOnlyAudioThroughTheLastPartialFrame() throws {
    let total = Int(EchoSampleRate) + 37
    var generator = SpeechLikeSignal(seed: 123, fundamental: 130)
    let voice = (0..<total).map { generator.sample($0) }
    let cleaned = try filter(microphone: voice, render: nil)
    #expect(cleaned.count == voice.count)
    #expect(Double(dot(cleaned, voice, 0..<total)) / power(voice, 0..<total) > 0.85)
    #expect(power(cleaned, (total - 37)..<total) > 0)
}

private func filter(microphone: [Int16], render: [Int16]?) throws -> [Int16] {
    let rate = Int32(EchoSampleRate)
    let origin = CMTime(value: 100, timescale: 1)
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: Double(rate), channels: 1, interleaved: true
    ))
    var cleaned: [Int16] = []
    let removal = try PlaybackEchoRemoval(origin: origin) { buffer, time in
        let index = CMTimeConvertScale(time - origin, timescale: rate, method: .roundHalfAwayFromZero).value
        #expect(index == Int64(cleaned.count))
        let samples = try #require(buffer.int16ChannelData?.pointee)
        cleaned.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }

    // Non-frame-aligned packets and one packet of reference callback lag.
    var lastRender: Range<Int>?
    for start in stride(from: 0, to: microphone.count, by: 183) {
        let range = start..<min(start + 183, microphone.count)
        try removal.appendCapture(
            audioBuffer(microphone[range], format: format),
            at: origin + CMTime(value: Int64(start), timescale: rate)
        )
        if let render, let lastRender {
            try removal.appendRender(
                audioBuffer(render[lastRender], format: format),
                at: origin + CMTime(value: Int64(lastRender.lowerBound), timescale: rate)
            )
        }
        lastRender = range
    }
    if let render, let lastRender {
        try removal.appendRender(
            audioBuffer(render[lastRender], format: format),
            at: origin + CMTime(value: Int64(lastRender.lowerBound), timescale: rate)
        )
    }
    try removal.finish()
    return cleaned
}

private func audioBuffer(_ samples: ArraySlice<Int16>, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
    let output = try #require(buffer.int16ChannelData?.pointee)
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() { output[index] = sample }
    return buffer
}

private func power(_ samples: [Int16], _ range: Range<Int>) -> Double {
    Double(dot(samples, samples, range))
}

private func dot(_ lhs: [Int16], _ rhs: [Int16], _ range: Range<Int>) -> Int64 {
    range.reduce(0) { $0 + Int64(lhs[$1]) * Int64(rhs[$1]) }
}

private struct SpeechLikeSignal {
    private var seed: UInt32
    private let fundamental: Double
    private var shapedNoise: Double = 0

    init(seed: UInt32, fundamental: Double) {
        self.seed = seed
        self.fundamental = fundamental
    }

    mutating func sample(_ index: Int) -> Int16 {
        seed = 1_664_525 &* seed &+ 1_013_904_223
        let noise = Double(Int16(bitPattern: UInt16(truncatingIfNeeded: seed >> 16))) / 32_768
        shapedNoise += 0.35 * (noise - shapedNoise)
        let time = Double(index) / Double(EchoSampleRate)
        let phase = 2 * Double.pi * fundamental * time + 8 * sin(time * 4)
        let envelope = 0.35 + 0.30 * sin(time * 27) + 0.18 * sin(time * 43)
        let signal = sin(phase) + 0.33 * sin(phase * 5) + 0.19 * sin(phase * 9) + 1.6 * shapedNoise
        return Int16(clamping: Int(signal * envelope * 12_000))
    }
}
