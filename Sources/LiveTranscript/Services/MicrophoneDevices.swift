import AVFoundation
import CoreAudio
import Foundation

enum MicrophoneDevices {
    static func available() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
        ).devices.filter(\.isConnected)
    }

    static func systemDefault() -> AVCaptureDevice? {
        var address = defaultInputAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
           device != kAudioObjectUnknown {
            address.mSelector = kAudioDevicePropertyDeviceUID
            var uid: Unmanaged<CFString>?
            size = UInt32(MemoryLayout.size(ofValue: uid))
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
               let uid, let input = AVCaptureDevice(uniqueID: uid.takeRetainedValue() as String),
               input.isConnected, input.hasMediaType(.audio) {
                return input
            }
        }
        return AVCaptureDevice.default(for: .audio).flatMap { $0.isConnected ? $0 : nil }
    }

    static func resolve(preferredID: String?) -> AVCaptureDevice? {
        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID),
           device.isConnected, device.hasMediaType(.audio) {
            return device
        }
        return systemDefault()
    }

    fileprivate static let system = AudioObjectID(kAudioObjectSystemObject)
    fileprivate static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

final class MicrophoneDeviceObservation {
    private let defaultListener: AudioObjectPropertyListenerBlock
    private let listensToDefault: Bool
    private let tokens: [any NSObjectProtocol]

    init(onChange: @escaping @Sendable () -> Void) {
        let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        defaultListener = listener
        var address = MicrophoneDevices.defaultInputAddress
        listensToDefault = AudioObjectAddPropertyListenerBlock(
            MicrophoneDevices.system, &address, .main, listener
        ) == noErr
        tokens = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                if let device = notification.object as? AVCaptureDevice, device.hasMediaType(.audio) { onChange() }
            }
        }
    }

    deinit {
        if listensToDefault {
            var address = MicrophoneDevices.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(MicrophoneDevices.system, &address, .main, defaultListener)
        }
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
