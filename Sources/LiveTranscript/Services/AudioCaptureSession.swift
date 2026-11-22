import AVFoundation
import CoreMedia
import Foundation

/// Control operations and callback processing use separate serial queues.
final class AudioCaptureSession: @unchecked Sendable {
    private let controlQueue = DispatchQueue(label: "live-transcript.capture-control", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "live-transcript.capture-processing", qos: .userInitiated)
    private lazy var systemAudio = SystemAudioCapture(processingQueue: processingQueue)
    private var microphone: MicrophoneCapture?

    func start(
        receiveMicrophone: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        receiveApplication: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            controlQueue.async {
                do {
                    try self.systemAudio.start(receive: receiveApplication, onError: onError)
                    let microphone = MicrophoneCapture(
                        processingQueue: self.processingQueue, receive: receiveMicrophone, onError: onError
                    )
                    self.microphone = microphone
                    try microphone.start()
                    continuation.resume()
                } catch {
                    self.stopOnControlQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                self.stopOnControlQueue()
                continuation.resume()
            }
        }
    }

    private func stopOnControlQueue() {
        microphone?.stop()
        systemAudio.stop()
        // The output delegate can already have an audio buffer queued when stop is called.
        processingQueue.sync {}
        microphone = nil
    }
}
