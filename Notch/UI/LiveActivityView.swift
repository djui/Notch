import AppKit
import SwiftUI

struct LiveActivityView: View {
    let activity: LiveActivityKind

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
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
        }
    }

    @ViewBuilder
    private func focusSymbol(_ focus: FocusLiveActivity) -> some View {
        let primary = Color.focusTint(focus.tintColorName)
        if let secondaryName = focus.secondaryTintColorName {
            Image(systemName: focus.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary, Color.focusTint(secondaryName))
                .symbolRenderingMode(.palette)
        } else {
            Image(systemName: focus.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary)
                .symbolRenderingMode(.hierarchical)
        }
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
        }
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
