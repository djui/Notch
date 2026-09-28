import CoreAudio
import Foundation

/// Announces Bluetooth headphones becoming the output, with battery levels when macOS reports them.
@MainActor
final class AudioRouteMonitor {
    struct Headphones: Equatable {
        var name: String
        var battery: String?
    }

    var onConnect: ((Headphones) -> Void)?
    var onBattery: ((Headphones) -> Void)?

    private var listener: AudioListener?
    private var current: AudioObjectID?

    func start() {
        stop()
        current = AudioDevices.defaultOutput
        listener = AudioListener(
            object: AudioObjectID(kAudioObjectSystemObject),
            address: AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in
            self?.outputChanged()
        }
    }

    func stop() {
        listener = nil
    }

    private func outputChanged() {
        let device = AudioDevices.defaultOutput
        defer { current = device }
        guard let device, device != current, AudioDevices.isBluetooth(device),
              let name = AudioDevices.name(of: device)
        else { return }
        onConnect?(Headphones(name: name))
        Task { [weak self] in
            // Battery levels show up in the Bluetooth report a moment after connecting.
            try? await Task.sleep(for: .seconds(1.5))
            let battery = await Task.detached(priority: .utility) { Self.batteryDescription(for: name) }.value
            guard let battery else { return }
            self?.onBattery?(Headphones(name: name, battery: battery))
        }
    }

    /// “L 80% · R 75% · Case 40%”, or the single level for other headphones.
    nonisolated static func batteryDescription(for name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let info = findDevice(named: name, in: json) else { return nil }
        let parts: [(String, String)] = [
            ("L", "device_batteryLevelLeft"),
            ("R", "device_batteryLevelRight"),
            ("Case", "device_batteryLevelCase"),
            ("", "device_batteryLevelMain"),
        ]
        let levels = parts.compactMap { label, key -> String? in
            guard let value = info[key] as? String else { return nil }
            return label.isEmpty ? value : "\(label) \(value)"
        }
        return levels.isEmpty ? nil : levels.joined(separator: " · ")
    }

    private nonisolated static func findDevice(named name: String, in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if let match = dict[name] as? [String: Any], match.keys.contains(where: { $0.hasPrefix("device_") }) {
                return match
            }
            for value in dict.values {
                if let found = findDevice(named: name, in: value) { return found }
            }
        } else if let list = json as? [Any] {
            for value in list {
                if let found = findDevice(named: name, in: value) { return found }
            }
        }
        return nil
    }
}
