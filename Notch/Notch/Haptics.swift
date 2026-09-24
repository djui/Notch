import AppKit
import IOKit

/// Taps the Force Touch trackpad.
///
/// `NSHapticFeedbackManager` only plays for the frontmost app, and Notch usually isn't while
/// hovering, so this drives the trackpad's actuator through the private MultitouchSupport
/// framework and falls back to AppKit when no actuator can be opened.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private typealias CreateActuator = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenActuator = @convention(c) (CFTypeRef) -> Int32
    private typealias Actuate = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private let createActuator: CreateActuator?
    private let openActuator: OpenActuator?
    private let actuate: Actuate?
    private var actuators: [CFTypeRef]?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        createActuator = symbol("MTActuatorCreateFromDeviceID", as: CreateActuator.self)
        openActuator = symbol("MTActuatorOpen", as: OpenActuator.self)
        actuate = symbol("MTActuatorActuate", as: Actuate.self)
    }

    func tap() {
        if actuators == nil { actuators = openActuators() }
        guard let actuate, let actuators, !actuators.isEmpty else {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            return
        }
        let played = actuators.map { actuate($0, 6, 0, 0, 0) == 0 }
        // Trackpads come and go (e.g. a Magic Trackpad); rescan on the next tap.
        if played.contains(false) { self.actuators = nil }
    }

    private func openActuators() -> [CFTypeRef] {
        guard let createActuator, let openActuator else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var actuators: [CFTypeRef] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let id = IORegistryEntryCreateCFProperty(service, "Multitouch ID" as CFString, nil, 0)?
                .takeRetainedValue() as? UInt64,
                let actuator = createActuator(id)?.takeRetainedValue(),
                openActuator(actuator) == 0
            else { continue }
            actuators.append(actuator)
        }
        return actuators
    }
}
