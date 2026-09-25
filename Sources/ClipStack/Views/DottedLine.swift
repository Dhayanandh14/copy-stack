import SwiftUI

/// A dashed horizontal rule. Reads as texture between rows rather than as a
/// hard rule, which suits a dense list better than a solid divider.
struct DottedLine: View {
    var color: Color = Color.primary.opacity(0.14)

    var body: some View {
        Rule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .foregroundStyle(color)
            .frame(height: 1)
    }

    private struct Rule: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
