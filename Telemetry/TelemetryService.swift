import Foundation

/// Owns the polling timer and dispatches sample calls to all registered
/// providers. Each tick:
///  1. Walks every provider, awaits its async `sample()`.
///  2. Appends the resulting snapshot to that provider's `SampleStore`.
///  3. Fires `onUpdate` once so the UI can re-render.
///
/// The single-timer design keeps autoreleased object churn and runloop
/// interleaving down — same property the Phase 1 `DispatchSourceTimer` had.
///
/// `SMCKit` is an `actor`, so `sample()` is async. We launch the
/// sampling work in a `Task` per tick; the timer itself stays synchronous
/// and non-blocking on the main queue.
@MainActor
final class TelemetryService {
    private var providers: [(provider: TelemetryProvider, store: SampleStore)] = []
    private var timer: DispatchSourceTimer?

    /// Called on the main queue after every successful sample pass.
    var onUpdate: ((TelemetryService) -> Void)?

    /// Polling interval in seconds. Default 1 Hz. Mutable so the user can
    /// change it at runtime via `setInterval(_:)`.
    private var interval: TimeInterval

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    /// Register a provider. Probing is the provider's responsibility
    /// (done in its own `init`); we just pair it with a fresh store.
    func add(_ provider: TelemetryProvider, storeCapacity: Int = 60) {
        let store = SampleStore(capacity: storeCapacity)
        providers.append((provider, store))
    }

    /// Look up the sample store for a given provider. Used by the UI
    /// to read history for the sparkline and chart.
    func store(for provider: TelemetryProvider) -> SampleStore? {
        providers.first(where: { $0.provider === provider })?.store
    }

    func start() {
        // Take one immediate sample so the UI has data on first render.
        Task { [weak self] in await self?.tick() }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            autoreleasepool {
                guard let self else { return }
                Task { await self.tick() }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Update the polling interval. If the service is already running,
    /// re-arms the existing `DispatchSourceTimer` in place — the next
    /// tick fires `new` seconds from now (we don't fire immediately on
    /// a setting change, since the user is interacting with a picker,
    /// not asking for a fresh sample). If `start()` hasn't been called
    /// yet, just remembers the value for when it does.
    func setInterval(_ new: TimeInterval) {
        interval = new
        guard let timer else { return }
        timer.schedule(
            deadline: .now() + new,
            repeating: new,
            leeway: .milliseconds(50)
        )
    }

    private func tick() async {
        for (provider, store) in providers {
            // No-op for unavailable providers — they return [] from sample().
            let snapshot = await provider.sample()
            store.append(snapshot)
        }
        onUpdate?(self)
    }
}
