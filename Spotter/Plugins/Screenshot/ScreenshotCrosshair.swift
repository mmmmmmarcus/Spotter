import CoreGraphics

/// Vector geometry transcribed from the 35×35 Union.svg supplied for Spotter's capture cursor.
enum ScreenshotCrosshair {
    static let size = CGSize(width: 35, height: 35)
    static let center = CGPoint(x: 17.5, y: 17.5)
    static let outlineWidth: CGFloat = 2
    static let shadowPadding: CGFloat = 4
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowBlur: CGFloat = 2
    static let cursorSize = CGSize(
        width: size.width + shadowPadding * 2,
        height: size.height + shadowPadding * 2)
    static let cursorHotSpot = CGPoint(
        x: center.x + shadowPadding,
        y: center.y + shadowPadding)

    static func makePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 17.5, y: 0))
        path.addCurve(
            to: CGPoint(x: 19, y: 1.5),
            control1: CGPoint(x: 18.3284, y: 0),
            control2: CGPoint(x: 19, y: 0.671573))
        path.addLine(to: CGPoint(x: 19, y: 4.58594))
        path.addCurve(
            to: CGPoint(x: 30.4131, y: 16),
            control1: CGPoint(x: 24.9809, y: 5.2731),
            control2: CGPoint(x: 29.7259, y: 10.0191))
        path.addLine(to: CGPoint(x: 33.5, y: 16))
        path.addCurve(
            to: CGPoint(x: 35, y: 17.5),
            control1: CGPoint(x: 34.3284, y: 16),
            control2: CGPoint(x: 35, y: 16.6716))
        path.addCurve(
            to: CGPoint(x: 33.5, y: 19),
            control1: CGPoint(x: 35, y: 18.3284),
            control2: CGPoint(x: 34.3284, y: 19))
        path.addLine(to: CGPoint(x: 30.4131, y: 19))
        path.addCurve(
            to: CGPoint(x: 19, y: 30.4131),
            control1: CGPoint(x: 29.7259, y: 24.9809),
            control2: CGPoint(x: 24.9809, y: 29.7259))
        path.addLine(to: CGPoint(x: 19, y: 33.5))
        path.addCurve(
            to: CGPoint(x: 17.5, y: 35),
            control1: CGPoint(x: 19, y: 34.3284),
            control2: CGPoint(x: 18.3284, y: 35))
        path.addCurve(
            to: CGPoint(x: 16, y: 33.5),
            control1: CGPoint(x: 16.6716, y: 35),
            control2: CGPoint(x: 16, y: 34.3284))
        path.addLine(to: CGPoint(x: 16, y: 30.4131))
        path.addCurve(
            to: CGPoint(x: 4.58691, y: 19),
            control1: CGPoint(x: 10.0191, y: 29.7259),
            control2: CGPoint(x: 5.27412, y: 24.9809))
        path.addLine(to: CGPoint(x: 1.5, y: 19))
        path.addCurve(
            to: CGPoint(x: 0, y: 17.5),
            control1: CGPoint(x: 0.671573, y: 19),
            control2: CGPoint(x: 0, y: 18.3284))
        path.addCurve(
            to: CGPoint(x: 1.5, y: 16),
            control1: CGPoint(x: 0, y: 16.6716),
            control2: CGPoint(x: 0.671573, y: 16))
        path.addLine(to: CGPoint(x: 4.58691, y: 16))
        path.addCurve(
            to: CGPoint(x: 16, y: 4.58594),
            control1: CGPoint(x: 5.27413, y: 10.0191),
            control2: CGPoint(x: 10.0191, y: 5.2731))
        path.addLine(to: CGPoint(x: 16, y: 1.5))
        path.addCurve(
            to: CGPoint(x: 17.5, y: 0),
            control1: CGPoint(x: 16, y: 0.671573),
            control2: CGPoint(x: 16.6716, y: 0))
        path.closeSubpath()

        path.move(to: CGPoint(x: 7.6123, y: 19))
        path.addCurve(
            to: CGPoint(x: 16, y: 27.3867),
            control1: CGPoint(x: 8.26245, y: 23.3219),
            control2: CGPoint(x: 11.6782, y: 26.7365))
        path.addLine(to: CGPoint(x: 16, y: 19))
        path.closeSubpath()

        path.move(to: CGPoint(x: 19, y: 19))
        path.addLine(to: CGPoint(x: 19, y: 27.3867))
        path.addCurve(
            to: CGPoint(x: 27.3877, y: 19),
            control1: CGPoint(x: 23.3218, y: 26.7365),
            control2: CGPoint(x: 26.7376, y: 23.3219))
        path.closeSubpath()

        path.move(to: CGPoint(x: 19, y: 16))
        path.addLine(to: CGPoint(x: 27.3877, y: 16))
        path.addCurve(
            to: CGPoint(x: 19, y: 7.6123),
            control1: CGPoint(x: 26.7375, y: 11.6781),
            control2: CGPoint(x: 23.3219, y: 8.26246))
        path.closeSubpath()

        path.move(to: CGPoint(x: 16, y: 7.6123))
        path.addCurve(
            to: CGPoint(x: 7.6123, y: 16),
            control1: CGPoint(x: 11.6781, y: 8.26246),
            control2: CGPoint(x: 8.26246, y: 11.6781))
        path.addLine(to: CGPoint(x: 16, y: 16))
        path.closeSubpath()
        return path.copy()!
    }
}
