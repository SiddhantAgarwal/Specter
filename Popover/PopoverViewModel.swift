import Foundation
import SwiftUI

/// Snapshot of one provider's latest sample. Captured at the boundary
/// between the imperative `TelemetryService` and the SwiftUI popover
/// so the view never reads mutable state directly.
struct ProviderSnapshot: Identifiable {
    let id: ObjectIdentifier
    let providerName: String
    let isAvailable: Bool
    let latest: [Metric]
    /// Series for the history chart. Each entry is a `(label, [Double])`
    /// pair so the chart can pick the primary series.
    let history: [(label: String, values: [Double])]
}

/// Source of truth for the popover view. The `TelemetryService` calls
/// `tick()` once per second; the view's `@ObservedObject` re-renders.
///
/// We don't expose the providers or the service to the view — only
/// immutable snapshots. This keeps the SwiftUI side stateless and
/// the imperative side testable.
@MainActor
final class PopoverViewModel: ObservableObject {
    @Published private(set) var cpu: ProviderSnapshot?
    @Published private(set) var fan: ProviderSnapshot?

    /// How many samples the chart should show. 5 minutes at 1 Hz.
    static let historyWindow = 300

    /// Live settings mirror. SwiftUI views read this for the display
    /// unit; `@AppStorage` in `SettingsSection` writes to UserDefaults
    /// and the change observer on `SettingsStore` republishes here.
    let settings: SettingsStore

    private let service: TelemetryService
    private let cpuProvider: CPUTemperatureProvider
    private let fanProvider: FanSpeedProvider

    init(
        service: TelemetryService,
        cpu: CPUTemperatureProvider,
        fan: FanSpeedProvider,
        settings: SettingsStore
    ) {
        self.service = service
        self.cpuProvider = cpu
        self.fanProvider = fan
        self.settings = settings
    }

    func tick() {
        cpu = snapshot(for: cpuProvider)
        fan = snapshot(for: fanProvider)
    }

    private func snapshot(for provider: TelemetryProvider) -> ProviderSnapshot {
        let store = service.store(for: provider)
        return ProviderSnapshot(
            id: ObjectIdentifier(provider),
            providerName: provider.name,
            isAvailable: provider.isAvailable,
            latest: store?.latest() ?? [],
            history: store?.snapshotHistory(maxSamples: Self.historyWindow) ?? []
        )
    }
}
