import SwiftUI

/// MacBook-style notch: outward ears at the top corners, modest convex radii at the bottom.
struct NotchShape: Shape {
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
        Path(NotchPath.cgPath(in: rect, earRadius: earRadius, bottomRadius: bottomRadius))
    }
}
