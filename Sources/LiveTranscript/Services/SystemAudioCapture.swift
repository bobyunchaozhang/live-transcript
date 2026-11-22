import AudioCaptureRing
import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

/// The capture session owns this object on its control queue. The timer is the ring's sole reader.
final class SystemAudioCapture {
    private let processingQueue: DispatchQueue
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var reader: TapReader?
    private var timer: DispatchSourceTimer?

    init(processingQueue: DispatchQueue) {
        self.processingQueue = processingQueue
    }

    func start(
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) throws {
        do {
            try configure(receive: receive, onError: onError)
        } catch {
            stop()
            throw error
        }
    }

    private func configure(
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: ownAudioProcess())
        description.name = "会听应用音频"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try check(AudioHardwareCreateProcessTap(description, &tap), action: "创建应用音频采集")
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(
            AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &size, &streamDescription),
            action: "读取应用音频格式"
        )
        guard streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mChannelsPerFrame == 1,
              streamDescription.mBytesPerFrame > 0,
              let format = AVAudioFormat(streamDescription: &streamDescription)
        else { throw CaptureError.audioFormat }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "会听",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device),
            action: "创建系统音频输入"
        )

        guard let reader = TapReader(format: format, receive: receive, onError: onError) else {
            throw CaptureError.audioFormat
        }
        self.reader = reader
        try check(
            CaptureRingAttach(reader.ring, device, &ioProc),
            action: "连接系统音频输入"
        )
        guard let ioProc else { throw CaptureError.audioFormat }
        try check(AudioDeviceStart(device, ioProc), action: "开始采集应用音频")

        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(5))
        timer.setEventHandler { reader.drain() }
        self.timer = timer
        timer.activate()
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(device, ioProc)
            AudioDeviceDestroyIOProcID(device, ioProc)
            self.ioProc = nil
        }
        timer?.cancel()
        timer = nil
        if let reader {
            processingQueue.sync { reader.drain() }
            self.reader = nil
        }
        if device != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(device)
            device = kAudioObjectUnknown
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
    }

    private func ownAudioProcess() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var ownProcess = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &ownProcess
        )
        return status == noErr && ownProcess != kAudioObjectUnknown ? [ownProcess] : []
    }

    private func check(_ status: OSStatus, action: String) throws {
        guard status == noErr else { throw CaptureError.audioSystem(action: action, status: status) }
    }
}

private final class TapReader: @unchecked Sendable {
    let ring: OpaquePointer

    private let format: AVAudioFormat
    private let bytesPerFrame: UInt32
    private let receive: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private let onError: @Sendable (any Error) -> Void

    init?(
        format: AVAudioFormat,
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) {
        guard let ring = CaptureRingCreate() else { return nil }
        self.ring = ring
        self.format = format
        self.bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        self.receive = receive
        self.onError = onError
    }

    deinit { CaptureRingDestroy(ring) }

    func drain() {
        var data: UnsafeRawPointer?
        var byteCount: UInt32 = 0
        var hostTime: UInt64 = 0

        while CaptureRingPeek(ring, &data, &byteCount, &hostTime) {
            defer { CaptureRingConsume(ring) }
            guard let data, byteCount.isMultiple(of: bytesPerFrame),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: byteCount / bytesPerFrame)
            else {
                onError(CaptureError.audioFormat)
                continue
            }
            buffer.frameLength = byteCount / bytesPerFrame
            guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
                onError(CaptureError.audioFormat)
                continue
            }
            memcpy(destination, data, Int(byteCount))
            let timestamp = hostTime == 0 ? CMClock.hostTimeClock.time : CMClockMakeHostTimeFromSystemUnits(hostTime)
            receive(buffer, timestamp)
        }

        if CaptureRingHasDroppedAudio(ring) {
            onError(CaptureError.audioBacklog)
        }
    }
}
