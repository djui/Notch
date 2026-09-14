import SwiftUI

/// Overlay clip: MacBook-style notch ears, or a floating Dynamic Island capsule.
struct NotchShape: Shape {
    var style: NotchLayoutStyle = .notch
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(NotchPath.cgPath(in: rect, style: style, earRadius: earRadius, bottomRadius: bottomRadius))
    }
}
