import SwiftUI

/// One row in a popover section: a thin vertical accent bar, the metric
/// label on the left, and the formatted value on the right.
///
/// The value is `Double` in canonical °C; the display unit is taken
/// from `unit`. `.contentTransition(.numericText())` gives a smooth
/// count-up/down animation when the value changes — available on
/// macOS 13+.
struct MetricRow: View {
    let label: String
    let value: Double
    let unit: Settings.Unit
    let metricUnit: Metric.Unit

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 2, height: 14)
                .cornerRadius(1)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatted)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 1)
    }

    private var formatted: String {
        switch metricUnit {
        case .celsius:
            let display = unit.convertFromCelsius(value)
            return String(format: "%.1f%@", display, unit.symbol)
        case .rpm:
            return "\(Int(value.rounded())) RPM"
        }
    }
}
