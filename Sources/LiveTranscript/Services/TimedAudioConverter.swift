import AVFoundation
import CoreMedia
import Foundation

/// Resamples onto a monotonic timeline and keeps gaps in the source clock.
final class TimedAudioConverter {
    typealias Output = (AVAudioPCMBuffer, CMTime) throws -> Void

    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputEnd: CMTime?
    private var outputEnd: CMTime?

    init(format: AVAudioFormat) {
        self.format = format
    }

    func append(_ pcm: AVAudioPCMBuffer, at time: CMTime, emit: Output) throws {
        guard pcm.frameLength > 0 else { return }

        let hasGap = inputEnd.map { (time - $0).seconds >= 0.03 } ?? true
        if let converter, hasGap || converter.inputFormat != pcm.format {
            try flushConverter(converter, emit: emit)
            self.converter = nil
        }
        let duration = CMTime(value: Int64(pcm.frameLength), timescale: CMTimeScale(pcm.format.sampleRate))
        inputEnd = time + duration
        if hasGap {
            outputEnd = CMTimeMaximum(time, outputEnd ?? time)
        }
        try enqueue(convert(pcm), emit: emit)
    }

    func finish(emit: Output) throws {
        guard let converter else { return }
        try flushConverter(converter, emit: emit)
        self.converter = nil
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, emit: Output) throws {
        guard buffer.frameLength > 0 else { return }
        let start = outputEnd ?? .zero
        outputEnd = start + CMTime(value: Int64(buffer.frameLength), timescale: CMTimeScale(format.sampleRate))
        try emit(buffer, start)
    }

    private func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard input.format != format else { return input }

        if converter == nil {
            converter = AVAudioConverter(from: input.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw CaptureError.audioFormat }

        let scaledLength = Double(input.frameLength) * format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(scaledLength.rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CaptureError.audioFormat
        }

        var error: NSError?
        var pending: AVAudioPCMBuffer? = input
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let buffer = pending else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            pending = nil
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { throw error as (any Error)? ?? CaptureError.audioFormat }
        return output
    }

    private func flushConverter(_ converter: AVAudioConverter, emit: Output) throws {
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048) else {
                throw CaptureError.audioFormat
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error else { throw error as (any Error)? ?? CaptureError.audioFormat }
            try enqueue(output, emit: emit)
            if status != .haveData || output.frameLength == 0 { return }
        }
    }
}
