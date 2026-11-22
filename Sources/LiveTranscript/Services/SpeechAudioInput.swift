import AVFoundation
import CoreMedia
import Foundation

/// Capture callbacks and conversion run on the serial capture processing queue.
final class SpeechAudioInput: @unchecked Sendable {
    private let source: TranscriptSource
    private let continuation: AsyncStream<SpeechAudioChunk>.Continuation
    private let converter: TimedAudioConverter
    private let origin: CMTime
    private var failed = false

    init(
        source: TranscriptSource,
        format: AVAudioFormat,
        origin: CMTime,
        continuation: AsyncStream<SpeechAudioChunk>.Continuation
    ) {
        self.source = source
        self.continuation = continuation
        self.origin = origin
        converter = TimedAudioConverter(format: format)
    }

    func append(_ pcm: AVAudioPCMBuffer, at timestamp: CMTime) throws {
        guard !failed else { return }
        do {
            try converter.append(pcm, at: CMTimeMaximum(.zero, timestamp - origin), emit: enqueue)
        } catch {
            failed = true
            throw error
        }
    }

    func finish() throws {
        if !failed { try converter.finish(emit: enqueue) }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, at start: CMTime) throws {
        guard let samples = buffer.floatChannelData?.pointee else { throw CaptureError.audioFormat }
        let startSample = CMTimeConvertScale(start, timescale: BilingualDecoder.sampleRate, method: .roundHalfAwayFromZero)
        let chunk = SpeechAudioChunk(
            source: source, startSample: startSample.value,
            samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        )
        if case .dropped = continuation.yield(chunk) {
            throw CaptureError.audioBacklog
        }
    }
}
