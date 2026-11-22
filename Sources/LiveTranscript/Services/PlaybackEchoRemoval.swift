import AVFoundation
import CoreMedia
import EchoDSP
import Foundation

/// The capture queue feeds both streams. Stop drains that queue before finish().
final class PlaybackEchoRemoval: @unchecked Sendable {
    private struct Frame {
        let start: Int64
        let samples: [Int16]
        let count: Int
    }

    private static let rate = Int32(EchoSampleRate)
    private static let blockSize = Int(EchoFrameSamples)
    private static let maximumWait = Int64(EchoSampleRate) * 110 / 1_000

    private let filter: OpaquePointer
    private let origin: CMTime
    private let format: AVAudioFormat
    private let renderConverter: TimedAudioConverter
    private let captureConverter: TimedAudioConverter
    private let emit: TimedAudioConverter.Output
    private let silence = Array(repeating: Int16(0), count: blockSize)

    private var renderEnd: Int64?
    private var captureEnd: Int64 = 0
    private var incompleteStart: Int64 = 0
    private var incomplete: [Int16] = []
    private var pending: [Frame] = []
    private var previous: Frame?

    init(origin: CMTime, emit: @escaping TimedAudioConverter.Output) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: Double(Self.rate), channels: 1, interleaved: true
        ), let filter = echo_filter_create() else {
            throw CaptureError.audioFormat
        }
        self.format = format
        self.origin = origin
        self.filter = filter
        self.emit = emit
        renderConverter = TimedAudioConverter(format: format)
        captureConverter = TimedAudioConverter(format: format)
        incomplete.reserveCapacity(Self.blockSize)
    }

    deinit {
        echo_filter_destroy(filter)
    }

    func appendRender(_ buffer: AVAudioPCMBuffer, at timestamp: CMTime) throws {
        try renderConverter.append(buffer, at: relative(timestamp), emit: storeRender)
        try drain()
    }

    func appendCapture(_ buffer: AVAudioPCMBuffer, at timestamp: CMTime) throws {
        try captureConverter.append(buffer, at: relative(timestamp), emit: storeCapture)
        try drain()
    }

    func finish() throws {
        try renderConverter.finish(emit: storeRender)
        try captureConverter.finish(emit: storeCapture)
        queueIncomplete()
        try drain(force: true)
        if let previous {
            try process(Frame(start: previous.start + Int64(Self.blockSize), samples: silence, count: 0))
            self.previous = nil
        }
    }

    private func relative(_ timestamp: CMTime) -> CMTime {
        CMTimeMaximum(.zero, timestamp - origin)
    }

    private func position(_ time: CMTime) -> Int64 {
        CMTimeConvertScale(time, timescale: Self.rate, method: .roundHalfAwayFromZero).value
    }

    private func storeRender(_ buffer: AVAudioPCMBuffer, at time: CMTime) throws {
        guard let samples = buffer.int16ChannelData?.pointee else { throw CaptureError.audioFormat }
        let start = position(time)
        echo_filter_store_render(filter, start, samples, Int(buffer.frameLength))
        renderEnd = start + Int64(buffer.frameLength)
    }

    private func storeCapture(_ buffer: AVAudioPCMBuffer, at time: CMTime) throws {
        guard let data = buffer.int16ChannelData?.pointee else { throw CaptureError.audioFormat }
        let samples = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))
        let start = position(time)
        if !incomplete.isEmpty, start != incompleteStart + Int64(incomplete.count) {
            queueIncomplete()
        }

        var offset = 0
        while offset < samples.count {
            if incomplete.isEmpty {
                incompleteStart = start + Int64(offset)
            }
            let next = min(samples.count, offset + Self.blockSize - incomplete.count)
            incomplete.append(contentsOf: samples[offset..<next])
            if incomplete.count == Self.blockSize { queueIncomplete() }
            offset = next
        }
        captureEnd = start + Int64(samples.count)
    }

    private func queueIncomplete() {
        guard !incomplete.isEmpty else { return }
        let count = incomplete.count
        incomplete.append(contentsOf: silence.prefix(Self.blockSize - count))
        pending.append(Frame(start: incompleteStart, samples: incomplete, count: count))
        incomplete.removeAll(keepingCapacity: true)
    }

    private func drain(force: Bool = false) throws {
        while let frame = pending.first {
            let end = frame.start + Int64(Self.blockSize)
            let renderReady = renderEnd.map { $0 >= end + Int64(EchoReferenceLeadSamples) } ?? false
            guard force || renderReady || captureEnd >= end + Self.maximumWait else { return }
            pending.removeFirst()
            try process(frame)
        }
    }

    private func process(_ frame: Frame) throws {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Self.blockSize)),
              let data = output.int16ChannelData?.pointee
        else { throw CaptureError.audioFormat }

        echo_filter_process(filter, frame.start, frame.samples, data)
        defer { previous = frame }
        if let previous, previous.count > 0 {
            output.frameLength = AVAudioFrameCount(previous.count)
            let timestamp = origin + CMTime(value: previous.start, timescale: Self.rate)
            try emit(output, timestamp)
        }
    }
}
