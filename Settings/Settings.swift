import Foundation

/// User-tunable settings, persisted to `UserDefaults`.
///
/// Four knobs:
/// - `greenYellowThreshold`: temperatures below this render green
/// - `yellowRedThreshold`:   temperatures at or above this render red
/// - `unit`:                 display unit (°C or °F) — affects labels only,
///                           thresholds are always stored in °C
/// - `refreshInterval`:      how often the telemetry timer fires, in seconds.
///                           Lower = smoother chart and menu bar updates,
///                           higher = lower background CPU.
struct Settings: Equatable {
    var greenYellowThreshold: Double
    var yellowRedThreshold: Double
    var unit: Unit
    var refreshInterval: RefreshInterval

    static let `default` = Settings(
        greenYellowThreshold: 70,
        yellowRedThreshold: 85,
        unit: .celsius,
        refreshInterval: .oneSecond
    )

    /// Polling cadence for the telemetry timer. `rawValue` is the
    /// `TimeInterval` (seconds) used by `DispatchSourceTimer`. Persisted
    /// in `UserDefaults` as a `Double`.
    enum RefreshInterval: Double, CaseIterable, Identifiable {
        case halfSecond  = 0.5
        case oneSecond   = 1.0
        case twoSeconds  = 2.0
        case fiveSeconds = 5.0

        var id: Double { rawValue }

        /// Compact label for the segmented picker, e.g. `"1s"`.
        var shortLabel: String {
            switch self {
            case .halfSecond:  return "0.5s"
            case .oneSecond:   return "1s"
            case .twoSeconds:  return "2s"
            case .fiveSeconds: return "5s"
            }
        }
    }

    enum Unit: String, CaseIterable, Identifiable {
        case celsius = "C"
        case fahrenheit = "F"

        var id: String { rawValue }
        /// Display symbol, e.g. "°C".
        var symbol: String { "°\(rawValue)" }
        /// Short label, e.g. "Celsius".
        var displayName: String {
            switch self {
            case .celsius: return "Celsius"
            case .fahrenheit: return "Fahrenheit"
            }
        }

        func convertFromCelsius(_ celsius: Double) -> Double {
            switch self {
            case .celsius: return celsius
            case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
            }
        }

        func convertToCelsius(_ value: Double) -> Double {
            switch self {
            case .celsius: return value
            case .fahrenheit: return (value - 32.0) * 5.0 / 9.0
            }
        }
    }

    /// Color bucket for a temperature reading. The comparison happens in
    /// the user's chosen unit so the threshold "feels" right in either mode.
    enum ColorBucket { case green, yellow, red }

    func bucket(forCelsius celsius: Double) -> ColorBucket {
        let inUnit = unit.convertFromCelsius(celsius)
        if inUnit < greenYellowThreshold { return .green }
        if inUnit < yellowRedThreshold { return .yellow }
        return .red
    }
}

/// UserDefaults keys for `Settings`. Kept as a namespace rather than an
/// enum so the SwiftUI `@AppStorage("...")` strings can use the same
/// constants.
enum SettingsKey {
    static let greenYellowThreshold = "greenYellowThreshold"
    static let yellowRedThreshold = "yellowRedThreshold"
    static let unit = "unit"
    static let refreshInterval = "refreshInterval"
}
