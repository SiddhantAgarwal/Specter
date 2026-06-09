import Foundation

/// A single sensor reading at a point in time.
///
/// A `Metric` is the atomic unit of telemetry that flows through Specter.
/// Providers produce arrays of metrics on each sample; the popover renders
/// them as rows, the menu bar picks one to sparkline.
struct Metric: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: Double
    let unit: Unit

    enum Unit {
        case celsius
        case rpm
    }
}

/// A source of telemetry. Each provider owns its SMC keys (or whatever
/// underlying mechanism), probes availability at init, and produces a
/// list of `Metric`s on every sample tick.
///
/// Conformers must be `AnyObject` (reference type) so the
/// `TelemetryService` can key `SampleStore`s by `ObjectIdentifier`.
///
/// `sample()` is async because SMCKit exposes an actor-isolated API;
/// the `TelemetryService` ticks the providers from a `Task` so we don't
/// block the main thread.
protocol TelemetryProvider: AnyObject {
    /// Human-readable section name shown in the popover, e.g.
    /// "CPU Temperature", "Fan Speed".
    var name: String { get }

    /// `true` if at least one underlying sensor was found at init.
    /// When `false`, the popover hides the section entirely.
    var isAvailable: Bool { get }

    /// Read the current sensor values. May return an empty array
    /// if a read failed this tick (the section will render an empty
    /// state, not disappear).
    func sample() async -> [Metric]
}
