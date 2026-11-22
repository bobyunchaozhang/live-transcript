import BilingualASR
import Foundation
import OSLog

struct SpeechAssets: Sendable {
    let library: URL
    let model: URL

    init(root: URL = Bundle.main.bundleURL.appending(path: "Contents")) {
        library = root.appending(path: "Frameworks/libsherpa-onnx-c-api.dylib")
        model = root.appending(path: "Resources/BilingualSpeech")
    }

    func validate() throws {
        let files = [library, library.deletingLastPathComponent().appending(path: "libonnxruntime.dylib")]
            + ["encoder.int8.onnx", "decoder.onnx", "joiner.int8.onnx", "tokens.txt"].map { model.appending(path: $0) }
        guard files.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw CaptureError.speechAssetsMissing
        }
    }
}

struct SpeechAudioChunk: Sendable {
    let source: TranscriptSource
    let startSample: Int64
    let samples: [Float]
}

/// The recognizer is shared by two independent streams and used by one worker.
final class BilingualDecoder: @unchecked Sendable {
    static let sampleRate: Int32 = 16_000

    private final class Track {
        var stream: OpaquePointer?
        var origin: Int64 = 0
        var nextSample: Int64?
        var lastText = ""
    }

    private let engine: OpaquePointer
    private let microphone = Track()
    private let application = Track()
    private let jsonDecoder = JSONDecoder()

    init(assets: SpeechAssets = SpeechAssets()) throws {
        try assets.validate()
        var error = [CChar](repeating: 0, count: 512)
        guard let engine = ht_asr_create(assets.library.path, assets.model.path, &error, error.count) else {
            let reason = String(decoding: error.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            Logger(subsystem: "local.bob.LiveTranscript", category: "speech").error(
                "Could not initialize bilingual recognition: \(reason, privacy: .public)"
            )
            throw CaptureError.speechUnavailable
        }
        self.engine = engine
    }

    deinit {
        for track in [microphone, application] {
            if let stream = track.stream { ht_asr_stream_destroy(engine, stream) }
        }
        ht_asr_destroy(engine)
    }

    func consume(_ chunk: SpeechAudioChunk) throws -> [TranscriptUpdate] {
        let track = chunk.source == .microphone ? microphone : application
        var changes: [TranscriptUpdate] = []
        var gap = chunk.startSample - (track.nextSample ?? chunk.startSample)

        if gap >= Int64(Self.sampleRate) {
            if let final = try finish(track, source: chunk.source) { changes.append(final) }
            gap = 0
        }
        if track.stream == nil {
            guard let stream = ht_asr_stream_create(engine) else { throw CaptureError.speechUnavailable }
            track.stream = stream
            track.origin = chunk.startSample
        }
        guard let stream = track.stream else { throw CaptureError.speechUnavailable }

        if gap > 0 {
            let silence = [Float](repeating: 0, count: Int(gap))
            _ = ht_asr_stream_accept(engine, stream, silence, Int32(silence.count))
        }
        let skipped = min(chunk.samples.count, Int(max(0, -gap)))
        let updated = chunk.samples.withUnsafeBufferPointer { samples in
            ht_asr_stream_accept(engine, stream, samples.baseAddress?.advanced(by: skipped), Int32(samples.count - skipped))
        }
        track.nextSample = max(track.nextSample ?? 0, chunk.startSample + Int64(chunk.samples.count))
        let atEndpoint = ht_asr_stream_endpoint(engine, stream)

        if updated || atEndpoint {
            if let result = try read(track, source: chunk.source, final: atEndpoint) { changes.append(result) }
            if atEndpoint {
                ht_asr_stream_reset(engine, stream)
                track.lastText = ""
            }
        }
        return changes
    }

    func finish() throws -> [TranscriptUpdate] {
        let near = Result { try finish(microphone, source: .microphone) }
        let far = Result { try finish(application, source: .application) }
        return try [near.get(), far.get()].compactMap { $0 }
    }

    private func finish(_ track: Track, source: TranscriptSource) throws -> TranscriptUpdate? {
        guard let stream = track.stream else { return nil }
        defer {
            ht_asr_stream_destroy(engine, stream)
            track.stream = nil
            track.nextSample = nil
            track.lastText = ""
        }
        ht_asr_stream_finish(engine, stream)
        return try read(track, source: source, final: true)
    }

    private func read(_ track: Track, source: TranscriptSource, final: Bool) throws -> TranscriptUpdate? {
        guard let stream = track.stream, let json = ht_asr_stream_result(engine, stream) else {
            throw CaptureError.speechUnavailable
        }
        defer { ht_asr_result_destroy(engine, json) }
        let result = try jsonDecoder.decode(
            BilingualSnapshot.self, from: Data(bytes: json, count: strlen(json))
        )
        guard result.text != track.lastText || (final && !result.text.isEmpty) else { return nil }
        track.lastText = result.text
        let start = Double(track.origin) / Double(Self.sampleRate) + result.startTime
        let timing = result.characterTiming(startedAt: start)
        return TranscriptUpdate(
            source: source, offset: timing.first?.start ?? start,
            text: result.text, isFinal: final, timing: timing
        )
    }
}
