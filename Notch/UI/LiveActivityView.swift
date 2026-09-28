import AppKit
import SwiftUI

struct LiveActivityView: View {
    let activity: LiveActivityKind
    /// Width hidden behind the camera housing; leading and trailing content stay outside it.
    var centerGap: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: max(8, centerGap))
            trailing
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .charging:
            Text("Charging")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .lowPower:
            Text("Low Power")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .focus(let focus):
            focusSymbol(focus)
        case .agent(let agent):
            HStack(spacing: 5) {
                Image(systemName: agent.agent.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(agent.agent.tint)
                    .modifier(AttentionPulse(active: agent.state == .attention))
                Text(agent.agent.shortTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        case .meeting(let meeting):
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(meeting.calendarColor.map { Color(nsColor: $0) } ?? .red)
                Text(meeting.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        case .privacy(let privacy):
            HStack(spacing: 5) {
                if privacy.microphone {
                    Image(systemName: "mic.fill").foregroundStyle(Color.privacyMicrophone)
                }
                if privacy.camera {
                    Image(systemName: "video.fill").foregroundStyle(Color.privacyCamera)
                }
            }
            .font(.system(size: 11, weight: .bold))
        case .level(let level):
            Image(systemName: level.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18)
        case .headphones(let headphones):
            HStack(spacing: 5) {
                Image(systemName: headphones.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(headphones.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func focusSymbol(_ focus: FocusLiveActivity) -> some View {
        let primary = Color.focusTint(focus.tintColorName)
        let secondary = focus.secondaryTintColorName.map(Color.focusTint)
        if NSImage(systemSymbolName: focus.symbol, accessibilityDescription: nil) != nil {
            if let secondary {
                Image(systemName: focus.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primary, secondary)
                    .symbolRenderingMode(.palette)
            } else {
                Image(systemName: focus.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primary)
                    .symbolRenderingMode(.hierarchical)
            }
        } else if let image = NSImage.focusSymbol(named: focus.symbol) {
            Image(nsImage: configuredFocusSymbol(image, primary: primary, secondary: secondary))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
        }
    }

    private func configuredFocusSymbol(_ image: NSImage, primary: Color, secondary: Color?) -> NSImage {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let secondary {
            config = config.applying(.init(paletteColors: [NSColor(primary), NSColor(secondary)]))
        } else {
            config = config.applying(.init(hierarchicalColor: NSColor(primary)))
        }
        return image.withSymbolConfiguration(config) ?? image
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case .charging(let percent):
            HStack(spacing: 6) {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold))
                BatteryGlyph(percent: percent, charging: true, tint: Color(red: 0.32, green: 0.84, blue: 0.39))
            }
            .foregroundStyle(Color(red: 0.32, green: 0.84, blue: 0.39))
        case .lowPower(let percent):
            HStack(spacing: 6) {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold))
                BatteryGlyph(percent: percent, charging: false, tint: Color(red: 0.98, green: 0.82, blue: 0.22))
            }
            .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.22))
        case .focus(let focus):
            Text(focus.isOn ? focus.name : "Off")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        case .agent(let agent):
            Text(agent.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agent.state.tint(question: agent.isQuestion))
                .lineLimit(1)
                .layoutPriority(1)
        case .meeting(let meeting):
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(meeting.countdown(at: context.date))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }
            .layoutPriority(1)
        case .privacy(let privacy):
            Text(privacy.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(privacy.camera ? Color.privacyCamera : Color.privacyMicrophone)
                .lineLimit(1)
        case .level(let level):
            LevelBar(value: level.value)
                .frame(width: 56, height: 5)
        case .headphones(let headphones):
            Text(headphones.lowestBattery ?? "Connected")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

private struct LevelBar: View {
    var value: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
            }
        }
        .animation(.easeOut(duration: 0.12), value: value)
        .accessibilityHidden(true)
    }
}

extension Color {
    static let privacyMicrophone = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let privacyCamera = Color(red: 0.2, green: 0.84, blue: 0.29)
}

extension PrivacyLiveActivity {
    var label: String {
        switch (microphone, camera) {
        case (true, true): "Mic & Camera"
        case (false, true): "Camera on"
        default: "Mic on"
        }
    }
}

extension LevelMonitor.Level {
    var value: Float {
        switch self {
        case .volume(let value, let muted): muted ? 0 : value
        case .brightness(let value): value
        }
    }

    var symbolName: String {
        switch self {
        case .volume(let value, let muted):
            if muted || value == 0 { return "speaker.slash.fill" }
            return value < 0.33 ? "speaker.wave.1.fill" : value < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness(let value):
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}

extension AudioRouteMonitor.Headphones {
    var symbolName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// The emptier earbud, or the only level, so it fits beside the camera. The expanded
    /// Bluetooth menu has the rest.
    var lowestBattery: String? {
        guard let battery else { return nil }
        let levels = battery.split(separator: "·")
            .filter { !$0.contains("Case") }
            .compactMap { Int($0.filter(\.isNumber)) }
        return levels.min().map { "\($0)%" } ?? battery
    }

    /// “Djui’s AirPods Pro” becomes “AirPods Pro”.
    var shortName: String {
        for separator in ["’s ", "'s "] {
            if let range = name.range(of: separator) {
                return String(name[range.upperBound...])
            }
        }
        return name
    }
}

extension Meeting {
    func countdown(at date: Date) -> String {
        let seconds = start.timeIntervalSince(date)
        if seconds <= 30 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes < 60 ? "in \(minutes)m" : "in \(minutes / 60)h"
    }
}

private struct BatteryGlyph: View {
    var percent: Int
    var charging: Bool
    var tint: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.2, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.15)
                    .frame(width: 22, height: 11)

                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(tint)
                    .frame(width: max(2.5, 16.5 * CGFloat(percent) / 100), height: 6.6)
                    .frame(width: 16.5, alignment: .leading)

                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            Capsule()
                .fill(tint)
                .frame(width: 1.6, height: 4)
        }
        .accessibilityHidden(true)
    }
}

private extension Color {
    static func focusTint(_ name: String?) -> Color {
        Color(nsColor: NSColor.focusTint(named: name))
    }
}

private extension NSColor {
    static func focusTint(named raw: String?) -> NSColor {
        guard let raw, !raw.isEmpty else { return .systemIndigo }
        if let mapped = mappedSystemColor(raw) {
            return mapped
        }
        let selector = NSSelectorFromString(raw)
        if NSColor.responds(to: selector),
           let color = NSColor.perform(selector)?.takeUnretainedValue() as? NSColor {
            return color
        }
        return .systemIndigo
    }

    private static func mappedSystemColor(_ raw: String) -> NSColor? {
        var key = raw
        if key.hasPrefix("system") {
            key.removeFirst(6)
        }
        if key.hasSuffix("Color") {
            key.removeLast(5)
        }
        switch key.lowercased() {
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "mint": return .systemMint
        case "teal": return .systemTeal
        case "cyan": return .systemCyan
        case "blue": return .systemBlue
        case "indigo": return .systemIndigo
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "brown": return .systemBrown
        case "gray", "grey": return .systemGray
        default: return nil
        }
    }
}
