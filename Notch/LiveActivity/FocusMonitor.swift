import AppKit
import Darwin
import Foundation
import notify

struct FocusSnapshot: Equatable {
    var isOn: Bool
    var symbolName: String
    var name: String
    var modeIdentifier: String?
    var tintColorName: String = "systemIndigoColor"
    var secondaryTintColorName: String?
}

@MainActor
final class FocusMonitor {
    private(set) var snapshot = FocusSnapshot(
        isOn: false,
        symbolName: "moon.fill",
        name: "Focus",
        modeIdentifier: nil
    )
    var onChange: ((FocusSnapshot) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var pollTask: Task<Void, Never>?
    private var distributedTap: DistributedTap?
    private var notifyTokens: [Int32] = []

    func start() {
        stop()
        if let fromFile = Self.readSnapshot() {
            snapshot = fromFile
        }
        watchDirectory()
        observeSystemNotifications()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refreshFromFile()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        directorySource?.cancel()
        directorySource = nil
        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
        if let tap = distributedTap {
            DistributedNotificationCenter.default().removeObserver(tap)
            distributedTap = nil
        }
        for token in notifyTokens {
            notify_cancel(token)
        }
        notifyTokens.removeAll()
    }

    /// True when Notch can read the Focus assertion store (Full Disk Access).
    static var canReadAssertions: Bool {
        let assertionsURL = dndDirectory.appendingPathComponent("Assertions.json")
        return (try? Data(contentsOf: assertionsURL)) != nil
    }

    private func observeSystemNotifications() {
        let tap = DistributedTap { [weak self] isOn, userInfo in
            Task { @MainActor in
                self?.handleExternalState(isOn: isOn, userInfo: userInfo)
            }
        }
        distributedTap = tap
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            tap,
            selector: #selector(DistributedTap.enabled(_:)),
            name: Notification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            tap,
            selector: #selector(DistributedTap.disabled(_:)),
            name: Notification.Name("_NSDoNotDisturbDisabledNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        let names = [
            "com.apple.focus.status.changed",
            "com.apple.focus.assertion.state.changed",
            "com.apple.notificationcenter.dnd.state.changed"
        ]
        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshFromFile()
                }
            }
            if status == NOTIFY_STATUS_OK {
                notifyTokens.append(token)
            }
        }
    }

    private func watchDirectory() {
        let url = Self.dndDirectory
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        directoryFD = open(url.path, O_EVTONLY)
        guard directoryFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshFromFile()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }
        directorySource = source
        source.resume()
    }

    private func handleExternalState(isOn: Bool, userInfo: [AnyHashable: Any]?) {
        let hintedID = Self.modeIdentifier(fromUserInfo: userInfo)
        if let fromFile = Self.readSnapshot() {
            if isOn, !fromFile.isOn {
                let resolved = hintedID.map { Self.resolve(modeID: $0, modes: Self.modeMap(from: Self.modesURL)) }
                apply(
                    FocusSnapshot(
                        isOn: true,
                        symbolName: resolved?.symbol ?? snapshot.symbolName,
                        name: resolved?.name ?? snapshot.name,
                        modeIdentifier: hintedID ?? snapshot.modeIdentifier,
                        tintColorName: resolved?.tintColorName ?? snapshot.tintColorName,
                        secondaryTintColorName: resolved?.secondaryTintColorName ?? snapshot.secondaryTintColorName
                    )
                )
            } else if !isOn {
                apply(
                    FocusSnapshot(
                        isOn: false,
                        symbolName: snapshot.symbolName,
                        name: snapshot.name,
                        modeIdentifier: snapshot.modeIdentifier,
                        tintColorName: snapshot.tintColorName,
                        secondaryTintColorName: snapshot.secondaryTintColorName
                    )
                )
            } else {
                apply(fromFile)
            }
        } else if isOn {
            let resolved = hintedID.map { Self.resolve(modeID: $0, modes: [:]) }
            apply(
                FocusSnapshot(
                    isOn: true,
                    symbolName: resolved?.symbol ?? snapshot.symbolName,
                    name: resolved?.name ?? snapshot.name,
                    modeIdentifier: hintedID ?? snapshot.modeIdentifier,
                    tintColorName: resolved?.tintColorName ?? snapshot.tintColorName,
                    secondaryTintColorName: resolved?.secondaryTintColorName ?? snapshot.secondaryTintColorName
                )
            )
        } else {
            apply(
                FocusSnapshot(
                    isOn: false,
                    symbolName: snapshot.symbolName,
                    name: snapshot.name,
                    modeIdentifier: snapshot.modeIdentifier,
                    tintColorName: snapshot.tintColorName,
                    secondaryTintColorName: snapshot.secondaryTintColorName
                )
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshFromFile()
        }
    }

    private func refreshFromFile() {
        guard let fromFile = Self.readSnapshot() else { return }
        apply(fromFile)
    }

    private func apply(_ next: FocusSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    private static var dndDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    private static var modesURL: URL {
        dndDirectory.appendingPathComponent("ModeConfigurations.json")
    }

    private static func modeIdentifier(fromUserInfo userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }
        let keys = [
            "assertionDetailsModeIdentifier",
            "modeIdentifier",
            "DNDModeIdentifier",
            "identifier",
        ]
        for key in keys {
            if let value = displayString(userInfo[key]), knownModes[value] != nil || value.contains(".") {
                return value
            }
        }
        return nil
    }

    /// `nil` when the assertion store exists but TCC blocks the read.
    /// Never treat that as “Focus off”.
    private static func readSnapshot() -> FocusSnapshot? {
        let assertionsURL = dndDirectory.appendingPathComponent("Assertions.json")
        let modesURL = Self.modesURL
        if let data = try? Data(contentsOf: assertionsURL) {
            guard let json = dictionary(from: data) else {
                return FocusSnapshot(isOn: false, symbolName: "moon.fill", name: "Focus", modeIdentifier: nil)
            }
            let modeID = activeModeID(from: json)
            let modes = modeMap(from: modesURL)
            if let modeID {
                let resolved = resolve(modeID: modeID, modes: modes)
                return                 FocusSnapshot(
                    isOn: true,
                    symbolName: resolved.symbol,
                    name: resolved.name,
                    modeIdentifier: modeID,
                    tintColorName: resolved.tintColorName,
                    secondaryTintColorName: resolved.secondaryTintColorName
                )
            }
            return FocusSnapshot(isOn: false, symbolName: "moon.fill", name: "Focus", modeIdentifier: nil)
        }
        if FileManager.default.fileExists(atPath: assertionsURL.path) {
            return nil
        }
        return FocusSnapshot(isOn: false, symbolName: "moon.fill", name: "Focus", modeIdentifier: nil)
    }

    private static func dictionary(from data: Data) -> [String: Any]? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [String: Any]
        {
            return plist
        }
        return nil
    }

    private static func dataItems(from json: [String: Any]) -> [[String: Any]] {
        if let items = json["data"] as? [[String: Any]] {
            return items
        }
        if let item = json["data"] as? [String: Any] {
            return [item]
        }
        return []
    }

    private static func activeModeID(from json: [String: Any]) -> String? {
        var best: (id: String, timestamp: Double)?

        func consider(id: String?, timestamp: Double?) {
            guard let id, !id.isEmpty else { return }
            let ts = timestamp ?? -.greatestFiniteMagnitude
            if let current = best {
                if ts >= current.timestamp {
                    best = (id, ts)
                }
            } else {
                best = (id, ts)
            }
        }

        for item in dataItems(from: json) {
            if let records = item["storeAssertionRecords"] as? [[String: Any]] {
                for record in records {
                    let details = record["assertionDetails"] as? [String: Any]
                    consider(
                        id: details?["assertionDetailsModeIdentifier"] as? String,
                        timestamp: doubleValue(record["assertionStartDateTimestamp"])
                    )
                }
            }
            consider(
                id: item["assertionDetailsModeIdentifier"] as? String,
                timestamp: doubleValue(item["assertionStartDateTimestamp"])
            )
        }
        return best?.id
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private struct ModeInfo {
        var name: String
        var symbol: String
        var tintColorName: String
        var secondaryTintColorName: String?
    }

    private static func resolve(modeID: String, modes: [String: ModeInfo]) -> ModeInfo {
        if let mode = modes[modeID] {
            return mode
        }
        return fallbackInfo(for: modeID)
    }

    private static func modeMap(from url: URL) -> [String: ModeInfo] {
        guard let data = try? Data(contentsOf: url),
              let json = dictionary(from: data)
        else { return [:] }

        var result: [String: ModeInfo] = [:]
        for item in dataItems(from: json) {
            collectModes(from: item["modeConfigurations"], into: &result)
        }
        collectModes(from: json["modeConfigurations"], into: &result)
        return result
    }

    private static func collectModes(from raw: Any?, into result: inout [String: ModeInfo]) {
        if let dict = raw as? [String: Any] {
            if dict["mode"] != nil {
                indexMode(from: dict, mapKey: nil, into: &result)
            } else {
                for (key, value) in dict {
                    if let nested = value as? [String: Any], nested["mode"] != nil {
                        indexMode(from: nested, mapKey: key, into: &result)
                    } else {
                        collectModes(from: value, into: &result)
                    }
                }
            }
        } else if let array = raw as? [Any] {
            for value in array {
                collectModes(from: value, into: &result)
            }
        }
    }

    private static func indexMode(
        from dict: [String: Any],
        mapKey: String?,
        into result: inout [String: ModeInfo]
    ) {
        let mode = dict["mode"] as? [String: Any] ?? dict
        let modeIdentifier = displayString(mode["modeIdentifier"])
        let identifier = displayString(mode["identifier"])
        guard modeIdentifier != nil || identifier != nil || mapKey != nil else { return }

        let resolvedID = modeIdentifier ?? identifier ?? mapKey ?? ""
        let fallback = fallbackInfo(for: resolvedID)
        let name = displayString(mode["name"])
            ?? displayString(mode["localizedName"])
            ?? displayString(mode["displayName"])
            ?? fallback.name
        let rawSymbol = displayString(mode["symbolImageName"])
            ?? displayString(mode["sfSymbolName"])
            ?? fallback.symbol
        let symbol = availableSymbol(rawSymbol) ?? availableSymbol(fallback.symbol) ?? "moon.fill"
        let descriptorTints = stringList(mode["symbolDescriptorTintColorNames"])
        let tint = descriptorTints.first
            ?? displayString(mode["tintColorName"])
            ?? fallback.tintColorName
        let secondary: String?
        if descriptorTints.count >= 2 {
            secondary = descriptorTints[1]
        } else if descriptorTints.isEmpty {
            secondary = fallback.secondaryTintColorName
        } else {
            secondary = nil
        }
        let info = ModeInfo(
            name: name,
            symbol: symbol,
            tintColorName: tint,
            secondaryTintColorName: secondary
        )

        if let mapKey, !mapKey.isEmpty {
            result[mapKey] = info
        }
        if let modeIdentifier {
            result[modeIdentifier] = info
        }
        if let identifier {
            result[identifier] = info
        }
    }

    private static func displayString(_ raw: Any?) -> String? {
        if let value = raw as? String {
            return value.isEmpty ? nil : value
        }
        if let dict = raw as? [String: Any] {
            for key in ["name", "localizedName", "displayName", "NSString", "string"] {
                if let value = displayString(dict[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func stringList(_ raw: Any?) -> [String] {
        if let values = raw as? [String] {
            return values.filter { !$0.isEmpty }
        }
        if let values = raw as? [Any] {
            return values.compactMap { displayString($0) }
        }
        return []
    }

    private static func availableSymbol(_ name: String) -> String? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : nil
    }

    private static let knownModes: [String: ModeInfo] = [
        "com.apple.donotdisturb.mode.default": ModeInfo(
            name: "Do Not Disturb", symbol: "moon.fill", tintColorName: "systemIndigoColor"
        ),
        "com.apple.donotdisturb.mode.driving": ModeInfo(
            name: "Driving", symbol: "car.fill", tintColorName: "systemIndigoColor"
        ),
        "com.apple.donotdisturb.mode.workout": ModeInfo(
            name: "Fitness", symbol: "figure.run", tintColorName: "systemGreenColor"
        ),
        "com.apple.focus.work": ModeInfo(
            name: "Work", symbol: "person.lanyardcard.fill", tintColorName: "systemGreenColor"
        ),
        "com.apple.focus.personal": ModeInfo(
            name: "Personal", symbol: "house.fill", tintColorName: "systemBlueColor"
        ),
        "com.apple.focus.personal-time": ModeInfo(
            name: "Personal", symbol: "house.fill", tintColorName: "systemBlueColor"
        ),
        "com.apple.focus.fitness": ModeInfo(
            name: "Fitness", symbol: "figure.run", tintColorName: "systemGreenColor"
        ),
        "com.apple.focus.gaming": ModeInfo(
            name: "Gaming", symbol: "gamecontroller.fill", tintColorName: "systemPurpleColor"
        ),
        "com.apple.focus.mindfulness": ModeInfo(
            name: "Mindfulness",
            symbol: "apple.mindfulness",
            tintColorName: "systemMintColor"
        ),
        "com.apple.focus.reading": ModeInfo(
            name: "Reading", symbol: "book.closed.fill", tintColorName: "systemOrangeColor"
        ),
        "com.apple.sleep.sleep-mode": ModeInfo(
            name: "Sleep", symbol: "bed.double.fill", tintColorName: "systemMintColor"
        ),
        "com.apple.focus.reduce-interruptions": ModeInfo(
            name: "Reduce Interruptions",
            symbol: "moon.fill",
            tintColorName: "systemPurpleColor",
            secondaryTintColorName: "systemTealColor"
        ),
    ]

    private static func fallbackInfo(for modeID: String) -> ModeInfo {
        var info = knownModes[modeID] ?? ModeInfo(
            name: "Focus",
            symbol: "moon.fill",
            tintColorName: "systemIndigoColor"
        )
        info.symbol = availableSymbol(info.symbol)
            ?? (modeID.contains("mindfulness") ? availableSymbol("brain.head.profile") : nil)
            ?? "moon.fill"
        return info
    }
}

private final class DistributedTap: NSObject {
    let onFire: (Bool, [AnyHashable: Any]?) -> Void

    init(onFire: @escaping (Bool, [AnyHashable: Any]?) -> Void) {
        self.onFire = onFire
    }

    @objc func enabled(_ notification: Notification) {
        onFire(true, notification.userInfo)
    }

    @objc func disabled(_ notification: Notification) {
        onFire(false, notification.userInfo)
    }
}
