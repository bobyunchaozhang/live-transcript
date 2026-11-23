import AVFoundation
import CoreMedia
import Foundation

final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let processingQueue: DispatchQueue
    private let receive: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private let onError: @Sendable (any Error) -> Void
    private var input: AVCaptureDeviceInput?
    private var runtimeObserver: (any NSObjectProtocol)?

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

    func start(preferredID: String?) throws {
        guard let device = MicrophoneDevices.resolve(preferredID: preferredID) else {
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

        self.input = input
        session.startRunning()
        guard session.isRunning else { throw CaptureError.microphoneUnavailable }
        runtimeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [onError] notification in
            // Device changes are handled by the input monitor without stopping application audio.
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            guard error?.code != .deviceWasDisconnected else { return }
            onError(CaptureError.microphoneInterrupted)
        }
    }

    func selectInput(preferredID: String?) throws {
        guard let device = MicrophoneDevices.resolve(preferredID: preferredID) else {
            throw CaptureError.microphoneUnavailable
        }
        if input?.device.uniqueID != device.uniqueID {
            let replacement = try AVCaptureDeviceInput(device: device)
            let previous = input
            session.beginConfiguration()
            if let previous { session.removeInput(previous) }
            if session.canAddInput(replacement) {
                session.addInput(replacement)
                input = replacement
            } else if let previous, previous.device.isConnected, session.canAddInput(previous) {
                session.addInput(previous)
            } else {
                input = nil
            }
            session.commitConfiguration()
            guard input === replacement else { throw CaptureError.microphoneUnavailable }
        }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { throw CaptureError.microphoneUnavailable }
    }

    func stop() {
        if let runtimeObserver {
            NotificationCenter.default.removeObserver(runtimeObserver)
            self.runtimeObserver = nil
        }
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
