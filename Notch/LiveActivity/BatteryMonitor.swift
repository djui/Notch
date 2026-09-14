import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    var isCharging: Bool
    var percent: Int
    var isLowPowerMode: Bool
}

@MainActor
final class BatteryMonitor {
    private(set) var snapshot = BatterySnapshot(isCharging: false, percent: 100, isLowPowerMode: false)
    var onChange: ((BatterySnapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var powerObserver: NSObjectProtocol?
    private var callbackContext: UnsafeMutableRawPointer?

    func start() {
        stop()
        let box = Unmanaged.passRetained(CallbackBox { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        })
        callbackContext = box.toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, callbackContext)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
        if let callbackContext {
            Unmanaged<CallbackBox>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    private func refresh() {
        let next = Self.readSnapshot()
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    private static func readSnapshot() -> BatterySnapshot {
        var isCharging = false
        var percent = 100
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                let type = raw[kIOPSTypeKey] as? String
                if type == kIOPSInternalBatteryType || type == "InternalBattery" {
                    isCharging = raw[kIOPSIsChargingKey] as? Bool ?? false
                    if let current = raw[kIOPSCurrentCapacityKey] as? Int {
                        if let max = raw[kIOPSMaxCapacityKey] as? Int, max > 0, current <= max {
                            percent = Int((Double(current) / Double(max) * 100).rounded())
                        } else {
                            percent = current
                        }
                    }
                    break
                }
            }
        }
        percent = min(100, max(0, percent))
        return BatterySnapshot(
            isCharging: isCharging,
            percent: percent,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

private final class CallbackBox {
    let fire: () -> Void
    init(_ fire: @escaping () -> Void) {
        self.fire = fire
    }
}
