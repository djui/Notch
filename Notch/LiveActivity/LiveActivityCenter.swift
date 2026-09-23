import Foundation
import SwiftUI

enum LiveActivityKind: Equatable {
    case charging(percent: Int)
    case lowPower(percent: Int)
    case focus(FocusLiveActivity)
}

struct FocusLiveActivity: Equatable {
    var name: String
    var symbol: String
    var isOn: Bool
    var tintColorName: String
    var secondaryTintColorName: String?
}

extension FocusSnapshot {
    func liveActivity(isOn: Bool? = nil) -> FocusLiveActivity {
        FocusLiveActivity(
            name: name,
            symbol: symbolName,
            isOn: isOn ?? self.isOn,
            tintColorName: tintColorName,
            secondaryTintColorName: secondaryTintColorName
        )
    }
}

@Observable
@MainActor
final class LiveActivityCenter {
    private(set) var current: LiveActivityKind?

    let battery = BatteryMonitor()
    let focus = FocusMonitor()

    private var dismissItem: DispatchWorkItem?
    private var pendingFocusOff: DispatchWorkItem?
    private var pendingFocusOn: DispatchWorkItem?
    private var lastCharging = false
    private var lastLowPower = false
    private var lastFocusOn = false
    private var lastFocusSymbol = "moon.fill"
    private var lastFocusName = "Focus"
    private var lastFocusModeID: String?
    private var lastFocusTint = "systemIndigoColor"
    private var lastFocusSecondaryTint: String?
    private var started = false
    private var batteryStarted = false
    private var focusStarted = false
    private var armingBattery = false

    func start() {
        guard !started else { return }
        started = true
        battery.onChange = { [weak self] snapshot in
            self?.handleBattery(snapshot)
        }
        focus.onChange = { [weak self] snapshot in
            self?.handleFocus(snapshot)
        }
        applyPreferences()
        lastFocusOn = focus.snapshot.isOn
        lastFocusSymbol = focus.snapshot.symbolName
        lastFocusName = focus.snapshot.name
        lastFocusModeID = focus.snapshot.modeIdentifier
        lastFocusTint = focus.snapshot.tintColorName
        lastFocusSecondaryTint = focus.snapshot.secondaryTintColorName
    }

    func stop() {
        started = false
        dismissItem?.cancel()
        dismissItem = nil
        pendingFocusOff?.cancel()
        pendingFocusOff = nil
        pendingFocusOn?.cancel()
        pendingFocusOn = nil
        current = nil
        battery.stop()
        focus.stop()
        batteryStarted = false
        focusStarted = false
    }

    func applyPreferences() {
        guard started else { return }
        let settings = AppModel.shared.settings
        if settings.showBattery {
            if !batteryStarted {
                armingBattery = true
                battery.start()
                armingBattery = false
                batteryStarted = true
                lastCharging = battery.snapshot.isCharging
                lastLowPower = battery.snapshot.isLowPowerMode
            }
        } else if batteryStarted {
            battery.stop()
            batteryStarted = false
            dismissBattery()
        }

        if settings.showFocus {
            if !focusStarted {
                focus.start()
                focusStarted = true
                lastFocusOn = focus.snapshot.isOn
                lastFocusSymbol = focus.snapshot.symbolName
                lastFocusName = focus.snapshot.name
                lastFocusModeID = focus.snapshot.modeIdentifier
                lastFocusTint = focus.snapshot.tintColorName
                lastFocusSecondaryTint = focus.snapshot.secondaryTintColorName
            }
        } else if focusStarted {
            pendingFocusOff?.cancel()
            pendingFocusOff = nil
            pendingFocusOn?.cancel()
            pendingFocusOn = nil
            focus.stop()
            focusStarted = false
            dismissFocus()
        }
    }

    func present(_ activity: LiveActivityKind, duration: TimeInterval = 4) {
        withAnimation(.easeInOut(duration: 0.32)) {
            current = activity
        }
        dismissItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.32)) {
                self?.current = nil
            }
            self?.dismissItem = nil
        }
        dismissItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func handleBattery(_ snapshot: BatterySnapshot) {
        if armingBattery || !AppModel.shared.settings.showBattery {
            lastCharging = snapshot.isCharging
            lastLowPower = snapshot.isLowPowerMode
            return
        }
        if snapshot.isCharging, !lastCharging {
            present(.charging(percent: snapshot.percent))
        } else if snapshot.isLowPowerMode, !lastLowPower {
            present(.lowPower(percent: snapshot.percent))
        } else if case .charging = current, snapshot.isCharging {
            current = .charging(percent: snapshot.percent)
        } else if case .lowPower = current, snapshot.isLowPowerMode {
            current = .lowPower(percent: snapshot.percent)
        }
        lastCharging = snapshot.isCharging
        lastLowPower = snapshot.isLowPowerMode
    }

    private func dismissBattery() {
        switch current {
        case .charging, .lowPower:
            withAnimation(.easeInOut(duration: 0.32)) {
                current = nil
            }
            dismissItem?.cancel()
            dismissItem = nil
        default:
            break
        }
    }

    private func dismissFocus() {
        if case .focus = current {
            withAnimation(.easeInOut(duration: 0.32)) {
                current = nil
            }
            dismissItem?.cancel()
            dismissItem = nil
        }
        lastFocusOn = false
        lastFocusModeID = nil
    }

    private func handleFocus(_ snapshot: FocusSnapshot) {
        guard AppModel.shared.settings.showFocus else { return }
        if snapshot.isOn {
            pendingFocusOff?.cancel()
            pendingFocusOff = nil
            let identityChanged = lastFocusOn
                && (
                    snapshot.modeIdentifier != lastFocusModeID
                    || snapshot.name != lastFocusName
                    || snapshot.symbolName != lastFocusSymbol
                    || snapshot.tintColorName != lastFocusTint
                    || snapshot.secondaryTintColorName != lastFocusSecondaryTint
                )
            if !lastFocusOn {
                if isUnresolved(snapshot) {
                    scheduleUnresolvedFocusOn(snapshot)
                } else {
                    pendingFocusOn?.cancel()
                    pendingFocusOn = nil
                    presentFocus(snapshot)
                }
            } else if identityChanged {
                pendingFocusOn?.cancel()
                pendingFocusOn = nil
                presentFocus(snapshot)
            } else if case .focus = current {
                current = .focus(snapshot.liveActivity(isOn: true))
                remember(snapshot)
            }
        } else {
            pendingFocusOn?.cancel()
            pendingFocusOn = nil
            if lastFocusOn || pendingFocusOff != nil {
                scheduleFocusOff()
            }
        }
    }

    private func presentFocus(_ snapshot: FocusSnapshot) {
        present(.focus(snapshot.liveActivity(isOn: true)))
        remember(snapshot)
    }

    private func remember(_ snapshot: FocusSnapshot) {
        lastFocusOn = true
        lastFocusSymbol = snapshot.symbolName
        lastFocusName = snapshot.name
        lastFocusModeID = snapshot.modeIdentifier
        lastFocusTint = snapshot.tintColorName
        lastFocusSecondaryTint = snapshot.secondaryTintColorName
    }

    private func isUnresolved(_ snapshot: FocusSnapshot) -> Bool {
        snapshot.modeIdentifier == nil
            && snapshot.name == "Focus"
            && snapshot.symbolName == "moon.fill"
    }

    private func scheduleUnresolvedFocusOn(_ snapshot: FocusSnapshot) {
        pendingFocusOn?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.presentFocus(snapshot)
            self.pendingFocusOn = nil
        }
        pendingFocusOn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scheduleFocusOff() {
        pendingFocusOff?.cancel()
        let activity = FocusLiveActivity(
            name: lastFocusName,
            symbol: lastFocusSymbol,
            isOn: false,
            tintColorName: lastFocusTint,
            secondaryTintColorName: lastFocusSecondaryTint
        )
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.present(.focus(activity))
            self.lastFocusOn = false
            self.lastFocusModeID = nil
            self.pendingFocusOff = nil
        }
        pendingFocusOff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
