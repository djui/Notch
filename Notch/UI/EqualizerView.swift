import SwiftUI

struct EqualizerView: View {
    var isPlaying: Bool
    var height: CGFloat = 12
    var barWidth: CGFloat = 2.1

    private let durations: [Double] = [1.18, 0.96, 1.42, 1.08]
    private let lows: [CGFloat] = [0.28, 0.22, 0.34, 0.24]
    private let highs: [CGFloat] = [1.0, 0.82, 0.94, 0.76]

    var body: some View {
        HStack(alignment: .center, spacing: 2.2) {
            ForEach(0..<4, id: \.self) { index in
                EqualizerBar(
                    isPlaying: isPlaying,
                    minHeight: height * lows[index],
                    maxHeight: height * highs[index],
                    duration: durations[index]
                )
                .frame(width: barWidth)
            }
        }
        .frame(width: barWidth * 4 + 2.2 * 3, height: height)
        .accessibilityHidden(true)
    }
}

private struct EqualizerBar: View {
    var isPlaying: Bool
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var duration: Double

    @State private var peaked = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.92))
            .frame(height: barHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(barAnimation, value: peaked)
            .onAppear {
                peaked = isPlaying
            }
            .onChange(of: isPlaying) { _, playing in
                peaked = playing
            }
    }

    private var barHeight: CGFloat {
        if isPlaying {
            return peaked ? maxHeight : minHeight
        }
        return minHeight
    }

    private var barAnimation: Animation {
        if isPlaying {
            return .easeInOut(duration: duration).repeatForever(autoreverses: true)
        }
        return .easeOut(duration: 0.4)
    }
}
