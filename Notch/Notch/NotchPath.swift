import CoreGraphics

enum NotchPath {
    static func cgPath(
        in rect: CGRect,
        style: NotchLayoutStyle = .notch,
        earRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> CGPath {
        switch style {
        case .notch:
            return notchPath(in: rect, earRadius: earRadius, bottomRadius: bottomRadius)
        case .island:
            let radius = min(max(max(earRadius, bottomRadius), 0), rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    private static func notchPath(in rect: CGRect, earRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let ear = min(max(earRadius, 0), rect.width / 4, rect.height / 2)
        let bottom = min(max(bottomRadius, 0), (rect.width - ear * 2) / 2, rect.height - ear)
        let left = rect.minX + ear
        let right = rect.maxX - ear

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
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
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
