import CoreAudio
import CoreMediaIO
import Foundation

/// Watches whether any app is using a microphone or camera. macOS does not say which app,
/// so the banner names the device kind only.
@MainActor
final class PrivacyMonitor {
    private(set) var microphoneInUse = false
    private(set) var cameraInUse = false
    var onChange: ((_ microphone: Bool, _ camera: Bool) -> Void)?

    private var audioListeners: [AudioListener] = []
    private var cameraListeners: [CameraListener] = []

    func start() {
        stop()
        rebuildListeners()
        microphoneInUse = Self.readMicrophone()
        cameraInUse = Self.readCamera()
    }

    func stop() {
        audioListeners.removeAll()
        cameraListeners.removeAll()
    }

    private func rebuildListeners() {
        audioListeners.removeAll()
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let devices = AudioListener(object: system, address: AudioDevices.address(kAudioHardwarePropertyDevices), handler: { [weak self] in
            self?.rebuildListeners()
            self?.refresh()
        }) {
            audioListeners.append(devices)
        }
        for device in AudioDevices.all where AudioDevices.hasInput(device) {
            if let listener = AudioListener(
                object: device,
                address: AudioDevices.address(kAudioDevicePropertyDeviceIsRunningSomewhere),
                handler: { [weak self] in self?.refresh() }
            ) {
                audioListeners.append(listener)
            }
        }
        cameraListeners = Self.cameraDevices().compactMap { device in
            CameraListener(device: device) { [weak self] in self?.refresh() }
        }
    }

    private func refresh() {
        let microphone = Self.readMicrophone()
        let camera = Self.readCamera()
        guard microphone != microphoneInUse || camera != cameraInUse else { return }
        let turnedOn = (microphone && !microphoneInUse) || (camera && !cameraInUse)
        microphoneInUse = microphone
        cameraInUse = camera
        if turnedOn {
            onChange?(microphone, camera)
        }
    }

    private static func readMicrophone() -> Bool {
        AudioDevices.all.contains { AudioDevices.hasInput($0) && AudioDevices.isRunningSomewhere($0) }
    }

    private static func readCamera() -> Bool {
        cameraDevices().contains { device in
            var address = CameraListener.runningAddress
            var running: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
            return status == 0 && running != 0
        }
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return [] }
        return devices
    }
}

private final class CameraListener {
    static let runningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    private let device: CMIOObjectID
    private var address = CameraListener.runningAddress
    private let block: CMIOObjectPropertyListenerBlock

    init?(device: CMIOObjectID, handler: @escaping () -> Void) {
        self.device = device
        block = { _, _ in handler() }
        guard CMIOObjectAddPropertyListenerBlock(device, &address, .main, block) == 0 else { return nil }
    }

    deinit {
        CMIOObjectRemovePropertyListenerBlock(device, &address, .main, block)
    }
}
