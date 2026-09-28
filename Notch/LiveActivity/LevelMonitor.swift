import AppKit
import AudioToolbox
import CoreAudio

/// Volume from CoreAudio, which catches every change: keys, menu bar, and apps. Brightness has
/// no public change notification, so it is read after the brightness keys.
@MainActor
final class LevelMonitor {
    enum Level: Equatable {
        case volume(Float, muted: Bool)
        case brightness(Float)
    }

    var onChange: ((Level) -> Void)?

    private var systemListener: AudioListener?
    private var deviceListeners: [AudioListener] = []
    private var keyMonitor: Any?
    /// Swallows the burst of callbacks a device switch produces.
    private var quietUntil = Date.distantPast
    private var lastVolume: Level?

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness")
        else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    func start() {
        stop()
        systemListener = AudioListener(
            object: AudioObjectID(kAudioObjectSystemObject),
            address: AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in
            self?.watchDefaultOutput()
        }
        watchDefaultOutput()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor in self?.handleSystemKey(event) }
        }
    }

    func stop() {
        systemListener = nil
        deviceListeners.removeAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func watchDefaultOutput() {
        deviceListeners.removeAll()
        quietUntil = Date().addingTimeInterval(0.6)
        guard let device = AudioDevices.defaultOutput else { return }
        lastVolume = currentVolume(of: device)
        let selectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]
        deviceListeners = selectors.compactMap { selector in
            AudioListener(object: device, address: AudioDevices.address(selector, scope: kAudioDevicePropertyScopeOutput)) { [weak self] in
                self?.volumeChanged(on: device)
            }
        }
    }

    private func currentVolume(of device: AudioObjectID) -> Level? {
        AudioDevices.outputVolume(of: device).map { .volume($0, muted: AudioDevices.isMuted(device)) }
    }

    private func volumeChanged(on device: AudioObjectID) {
        let level = currentVolume(of: device)
        defer { lastVolume = level }
        guard Date() > quietUntil, let level, level != lastVolume else { return }
        onChange?(level)
    }

    /// NX_KEYTYPE_BRIGHTNESS_UP (2) and _DOWN (3) arrive as system-defined events, subtype 8.
    private func handleSystemKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let key = (event.data1 & 0xFFFF_0000) >> 16
        let isDown = (event.data1 & 0xFF00) >> 8 == 0x0A
        guard isDown, key == 2 || key == 3, let getBrightness else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            var value: Float = 0
            guard getBrightness(CGMainDisplayID(), &value) == 0 else { return }
            self?.onChange?(.brightness(value))
        }
    }
}
