import CoreMedia
import Foundation

@MainActor
protocol RecordingSession: AnyObject {
    var markdown: MarkdownOutput { get }

    func startAudio(
        microphoneID: String?,
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) async throws
    func selectMicrophone(_ id: String?, completion: @escaping @Sendable (Result<Void, any Error>) -> Void)
    func stopAudio() async throws
}

@MainActor
final class LiveSession: RecordingSession {
    let markdown: MarkdownOutput

    private let decoder: BilingualDecoder
    private let origin: CMTime
    private var audio: LiveAudioRun?

    private init(decoder: BilingualDecoder, origin: CMTime, markdown: MarkdownOutput) {
        self.decoder = decoder
        self.origin = origin
        self.markdown = markdown
    }

    static func prepare(onStatus: @escaping @MainActor (String) -> Void) async throws -> any RecordingSession {
        try await MicrophoneCapture.requestPermission()
        try Task.checkCancellation()
        onStatus("正在准备中英文识别…")
        let decoder = try await Task.detached(priority: .userInitiated) { try BilingualDecoder() }.value
        try Task.checkCancellation()
        let origin = CMClock.hostTimeClock.time
        let markdown = try MarkdownOutput(startedAt: .now)
        return LiveSession(decoder: decoder, origin: origin, markdown: markdown)
    }

    func startAudio(
        microphoneID: String?,
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) async throws {
        try await MicrophoneCapture.requestPermission()
        try Task.checkCancellation()
        audio = try await LiveAudioRun.start(
            decoder: decoder, origin: origin, microphoneID: microphoneID, onUpdate: onUpdate, onError: onError
        )
    }

    func selectMicrophone(_ id: String?, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        audio?.selectMicrophone(id, completion: completion)
    }

    func stopAudio() async throws {
        guard let audio else { return }
        defer { self.audio = nil }
        try await audio.stop()
    }
}
