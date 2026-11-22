import AVFoundation
import CoreMedia
import Foundation

/// One uninterrupted capture interval. Pausing finishes this interval and releases both inputs.
@MainActor
struct LiveAudioRun {
    private let capture: AudioCaptureSession
    private let echoRemoval: PlaybackEchoRemoval
    private let microphone: SpeechAudioInput
    private let application: SpeechAudioInput
    private let input: AsyncStream<SpeechAudioChunk>.Continuation
    private let worker: Task<Void, any Error>

    static func start(
        decoder: BilingualDecoder,
        origin: CMTime,
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) async throws -> LiveAudioRun {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(BilingualDecoder.sampleRate), channels: 1
        ) else { throw CaptureError.audioFormat }

        let capture = AudioCaptureSession()
        let runOffset = (CMClock.hostTimeClock.time - origin).seconds
        let runStartedAt = Date()
        let (sequence, input) = AsyncStream<SpeechAudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(512))
        let microphone = SpeechAudioInput(source: .microphone, format: format, origin: origin, continuation: input)
        let application = SpeechAudioInput(source: .application, format: format, origin: origin, continuation: input)
        let echoRemoval = try PlaybackEchoRemoval(origin: origin, emit: microphone.append)
        let publish: @Sendable (TranscriptUpdate) async -> Void = { result in
            var update = result
            update.recordedAt = runStartedAt.addingTimeInterval(max(0, update.offset - runOffset))
            await onUpdate(update)
        }
        let worker = Task.detached(priority: .userInitiated) {
            do {
                for await chunk in sequence {
                    try Task.checkCancellation()
                    for update in try decoder.consume(chunk) { await publish(update) }
                }
                try Task.checkCancellation()
                for update in try decoder.finish() { await publish(update) }
            } catch {
                // Reset both decoder streams before this run gives back the shared model.
                _ = try? decoder.finish()
                if !(error is CancellationError) { onError(error) }
                throw error
            }
        }

        do {
            try await capture.start(
                receiveMicrophone: { buffer, timestamp in
                    do { try echoRemoval.appendCapture(buffer, at: timestamp) }
                    catch { onError(error) }
                },
                receiveApplication: { buffer, timestamp in
                    do {
                        try application.append(buffer, at: timestamp)
                        try echoRemoval.appendRender(buffer, at: timestamp)
                    } catch { onError(error) }
                },
                onError: onError
            )
            try Task.checkCancellation()
            return LiveAudioRun(
                capture: capture, echoRemoval: echoRemoval,
                microphone: microphone, application: application, input: input, worker: worker
            )
        } catch {
            await capture.stop()
            worker.cancel()
            input.finish()
            _ = await worker.result
            throw error
        }
    }

    func stop() async throws {
        await capture.stop()
        let echoResult = Result { try echoRemoval.finish() }
        let microphoneResult = Result { try microphone.finish() }
        let applicationResult = Result { try application.finish() }
        input.finish()
        try await worker.value
        try echoResult.get()
        try microphoneResult.get()
        try applicationResult.get()
    }
}
