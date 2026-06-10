import SwiftUI

/// The popover's settings section. Uses `@AppStorage` so changes persist
/// to `UserDefaults` automatically and the slider's value reflects the
/// last-saved state on re-open.
///
/// The slider values are *displayed* in the user's chosen unit but
/// *stored* in °C. The conversion is handled in the slider's binding.
struct SettingsSection: View {
    @AppStorage(SettingsKey.greenYellowThreshold) private var greenYellowCelsius: Double
        = Settings.default.greenYellowThreshold
    @AppStorage(SettingsKey.yellowRedThreshold) private var yellowRedCelsius: Double
        = Settings.default.yellowRedThreshold
    @AppStorage(SettingsKey.unit) private var unitRaw: String = Settings.default.unit.rawValue
    @AppStorage(SettingsKey.refreshInterval) private var refreshIntervalRaw: Double
        = Settings.default.refreshInterval.rawValue

    private var unit: Settings.Unit {
        Settings.Unit(rawValue: unitRaw) ?? .celsius
    }

    /// Bridges the `Double`-backed `@AppStorage` to the
    /// `Settings.RefreshInterval` enum the picker binds to.
    private var refreshInterval: Binding<Settings.RefreshInterval> {
        Binding(
            get: {
                Settings.RefreshInterval(rawValue: refreshIntervalRaw)
                    ?? Settings.default.refreshInterval
            },
            set: { refreshIntervalRaw = $0.rawValue }
        )
    }

    /// Range bounds for the slider. We let the user set the threshold
    /// anywhere from 30 to 110 in their chosen unit (≈ 0 to 230 °F).
    private var sliderBounds: ClosedRange<Double> {
        switch unit {
        case .celsius: return 30...110
        case .fahrenheit: return 90...230
        }
    }

    /// Binding adapter: the slider shows the value in `unit`, but writes
    /// the converted-to-°C value to the @AppStorage.
    private func displayBinding(forCelsius storage: Binding<Double>) -> Binding<Double> {
        Binding<Double>(
            get: { unit.convertFromCelsius(storage.wrappedValue) },
            set: { newDisplay in
                let clamped = min(max(newDisplay, sliderBounds.lowerBound), sliderBounds.upperBound)
                storage.wrappedValue = unit.convertToCelsius(clamped)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            thresholdRow(
                title: "Green → Yellow",
                display: displayBinding(forCelsius: $greenYellowCelsius)
            )
            thresholdRow(
                title: "Yellow → Red",
                display: displayBinding(forCelsius: $yellowRedCelsius)
            )

            HStack {
                Text("Unit")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $unitRaw) {
                    ForEach(Settings.Unit.allCases) { u in
                        Text(u.displayName).tag(u.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Refresh")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: refreshInterval) {
                    ForEach(Settings.RefreshInterval.allCases) { i in
                        Text(i.shortLabel).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    @ViewBuilder
    private func thresholdRow(title: String, display: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedThreshold(display.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            Slider(value: display, in: sliderBounds, step: 1)
        }
    }

    private func formattedThreshold(_ value: Double) -> String {
        String(format: "%.0f%@", value.rounded(), unit.symbol)
    }
}
