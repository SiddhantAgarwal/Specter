import SwiftUI

/// Renders a single-series line chart for the popover's history view.
/// Uses `Canvas` for direct Core Graphics drawing — much cheaper than
/// chaining `Path` views and gives us per-tick redraws at 1 Hz with
/// no measurable cost.
struct SparklineChart: View {
    let values: [Double]
    let range: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return }

            let stepX = size.width / CGFloat(values.count - 1)

            // Path through the (x, y) points.
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let normalized = (v - range.lowerBound) / span   // 0...1
                let y = size.height - (CGFloat(normalized) * size.height)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            // Fill under the line.
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(.accentColor.opacity(0.18)))

            // Stroke the line itself.
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}
