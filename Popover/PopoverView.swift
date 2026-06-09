import SwiftUI

/// The popover's main view. Reads from `PopoverViewModel` and re-renders
/// once per second when `viewModel.tick()` is called by the service, and
/// also when the user changes a setting (the view model republishes on
/// `UserDefaults.didChangeNotification` via `SettingsStore`).
struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel

    private var unit: Settings.Unit { viewModel.settings.settings.unit }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let cpu = viewModel.cpu, cpu.isAvailable {
                providerSection(title: cpu.providerName, snapshot: cpu)
                if let primary = cpu.history.first {
                    chartSection(values: primary.values)
                }
            }

            if let fan = viewModel.fan, fan.isAvailable {
                providerSection(title: fan.providerName, snapshot: fan)
            }

            Divider()
            SettingsSection()

            HStack {
                Spacer()
                Button("Quit Specter") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
                Spacer()
            }
        }
        .padding(14)
        // `.ignoresSafeArea()` tells SwiftUI to lay out the content
        // against the popover's full bounds rather than the popover's
        // safe area (which on macOS 26.5 includes insets for the
        // rounded-corner mask and the arrow). Without this, the top
        // of the content gets pushed below the safe-area top, and
        // depending on popover size/version, the first row can be
        // cropped.
        .ignoresSafeArea()
        // Explicit fixed size for the SwiftUI content so the hosting
        // view's reported size matches the popover's frame exactly.
        // This prevents `NSPopover` from re-framing itself based on
        // the SwiftUI view's intrinsic size mid-show.
        .frame(width: 280, height: 440)
    }

    // MARK: - Section helpers

    @ViewBuilder
    private func providerSection(title: String, snapshot: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            ForEach(snapshot.latest) { metric in
                MetricRow(
                    label: metric.label,
                    value: metric.value,
                    unit: unit,
                    metricUnit: metric.unit
                )
            }
        }
    }

    @ViewBuilder
    private func chartSection(values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HISTORY · LAST 5 MIN")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            // Values are canonical °C; convert at the view boundary so
            // the chart axis is in the user's chosen unit.
            let displayValues = values.map { unit.convertFromCelsius($0) }
            SparklineChart(
                values: displayValues,
                range: chartRange(for: displayValues)
            )
            .frame(height: 50)
        }
    }

    /// Auto-scale the y-axis to the data with a small visual margin.
    /// Values are already in the user's unit; bounds adapt.
    private func chartRange(for values: [Double]) -> ClosedRange<Double> {
        switch unit {
        case .celsius:
            let lo = max(30, (values.min() ?? 50) - 5)
            let hi = min(110, (values.max() ?? 70) + 5)
            return lo < hi ? lo...hi : 50...70
        case .fahrenheit:
            let lo = max(90, (values.min() ?? 130) - 9)
            let hi = min(230, (values.max() ?? 160) + 9)
            return lo < hi ? lo...hi : 130...160
        }
    }
}
