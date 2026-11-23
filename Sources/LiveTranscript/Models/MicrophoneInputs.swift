import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MicrophoneInputs {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String

        init(_ device: AVCaptureDevice) {
            id = device.uniqueID
            name = device.localizedName
        }
    }

    private static let preferenceKey = "preferredMicrophoneID"
    private let defaults: UserDefaults
    @ObservationIgnored private var observer: MicrophoneDeviceObservation?
    private(set) var devices: [Device] = []
    private(set) var systemDefault: Device?
    private(set) var preferredID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredID = defaults.string(forKey: Self.preferenceKey)
    }

    var preferredDevice: Device? { devices.first { $0.id == preferredID } }

    func select(_ id: String?) {
        preferredID = id
        defaults.set(id, forKey: Self.preferenceKey)
    }

    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        observer = MicrophoneDeviceObservation { [weak self] in
            Task { @MainActor in
                self?.refresh()
                onChange()
            }
        }
        refresh()
    }

    private func refresh() {
        let available = MicrophoneDevices.available().map(Device.init)
        let currentDefault = MicrophoneDevices.systemDefault().map(Device.init)
        systemDefault = currentDefault
        if let currentDefault, !available.contains(where: { $0.id == currentDefault.id }) {
            devices = available + [currentDefault]
        } else {
            devices = available
        }
    }
}
