import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let processingQueue: DispatchQueue
    private let receive: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private let onError: @Sendable (any Error) -> Void
    private var observers: [any NSObjectProtocol] = []

    init(
        processingQueue: DispatchQueue,
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) {
        self.processingQueue = processingQueue
        self.receive = receive
        self.onError = onError
    }

    static func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default:
            break
        }
        throw CaptureError.microphonePermission
    }

    func start() throws {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.first { $0.transportType == Int32(kAudioDeviceTransportTypeBuiltIn) }
        guard let device = builtIn ?? AVCaptureDevice.default(for: .audio) else {
            throw CaptureError.microphoneUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CaptureError.microphoneUnavailable
        }

        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: processingQueue)
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else { throw CaptureError.microphoneUnavailable }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) {
                [onError] _ in onError(CaptureError.microphoneInterrupted)
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) {
                [onError] _ in onError(CaptureError.microphoneInterrupted)
            },
        ]
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        session.stopRunning()
        output.setSampleBufferDelegate(nil, queue: nil)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0,
              let description = sampleBuffer.formatDescription
        else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples))
        else {
            onError(CaptureError.audioFormat)
            return
        }
        buffer.frameLength = buffer.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(sampleBuffer.numSamples), into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            onError(CaptureError.audioFormat)
            return
        }

        let timestamp = if let clock = session.synchronizationClock {
            clock.convertTime(sampleBuffer.presentationTimeStamp, to: CMClock.hostTimeClock)
        } else {
            sampleBuffer.presentationTimeStamp
        }
        receive(buffer, timestamp.isNumeric ? timestamp : CMClock.hostTimeClock.time)
    }
}
