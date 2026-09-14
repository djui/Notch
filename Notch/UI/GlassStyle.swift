import SwiftUI

/// Always-black hardware fill. Overlay UI stays dark via `preferredColorScheme`.
struct GlassPanelBackground: View {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var body: some View {
        NotchShape(earRadius: earRadius, bottomRadius: bottomRadius)
            .fill(Color.black)
    }
}

struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 16
    var selected: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.black)
            .overlay {
                shape.fill(Color.primary.opacity(selected ? 0.10 : 0.06))
            }
            .overlay {
                shape
                    .inset(by: 1)
                    .strokeBorder(Color.primary.opacity(selected ? 0.55 : 0.12), lineWidth: 1)
            }
    }
}
