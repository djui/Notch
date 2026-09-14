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
        let ear = min(max(earRadius, 0), rect.width / 4, rect.height / 2)
        let bottom = min(max(bottomRadius, 0), (rect.width - ear * 2) / 2, (rect.height - ear) / 2)
        let left = rect.minX + ear
        let right = rect.maxX - ear

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right ear points outward into the menu bar.
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.minY + ear),
            control: CGPoint(x: right, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: right, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: right - bottom, y: rect.maxY),
            control: CGPoint(x: right, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: left + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.maxY - bottom),
            control: CGPoint(x: left, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.minY + ear))
        // Top-left ear points outward into the menu bar.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
