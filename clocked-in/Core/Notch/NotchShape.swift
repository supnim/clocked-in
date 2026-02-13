import SwiftUI

struct NotchShape: Shape {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)

        // Control the depth of the "ear" curve based on the top corner radius
        // Smaller radius = tighter curve (closed state), larger radius = smoother curve (opened state)
        let earCurveDepth = topRadius * 0.45
        let earCurveWidth = topRadius * 1.2

        var path = Path()

        // Start at top-left after the ear curve
        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))

        // Top edge to top-right corner (before right ear)
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))

        // Top-right ear curve - the distinctive "scoop" inward
        // This creates the smooth transition from the top edge to the right side
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control1: CGPoint(x: rect.maxX - topRadius + earCurveWidth, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + topRadius - earCurveDepth)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))

        // Bottom-right corner (standard arc)
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))

        // Bottom-left corner (standard arc)
        path.addArc(
            center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))

        // Top-left ear curve - the distinctive "scoop" inward (mirror of right side)
        path.addCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + topRadius - earCurveDepth),
            control2: CGPoint(x: rect.minX + topRadius - earCurveWidth, y: rect.minY)
        )

        return path
    }
}
