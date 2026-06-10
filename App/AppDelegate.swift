import AppKit
import Combine

/// Top-level coordinator. Builds the telemetry stack, the menu bar
/// controller, and the popover controller; wires them together; starts
/// polling. Holds no UI state of its own — that's all in the
/// controllers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var service: TelemetryService?
    private var menuBar: MenuBarController?
    private var popover: PopoverController?
    private var settings: SettingsStore?

    /// Combine subscriptions kept alive for the lifetime of the app.
    /// Currently used to push the user's `refreshInterval` setting into
    /// the running `TelemetryService` so the change takes effect without
    /// a restart.
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Defer setup to the next runloop tick. The status bar is still
        // mid-layout when `applicationDidFinishLaunching` returns, and
        // synchronous NSStatusBar mutation can trip AppKit's
        // "layoutSubtreeIfNeeded" recursion guard.
        DispatchQueue.main.async { [weak self] in
            self?.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        service?.stop()
    }

    private func bootstrap() {
        Task { [weak self] in
            // Provider inits are async because they probe SMCKit (an actor).
            let cpu = await CPUTemperatureProvider()
            let fan = await FanSpeedProvider()
            await self?.wireUp(cpu: cpu, fan: fan)
        }
    }

    private func wireUp(cpu: CPUTemperatureProvider, fan: FanSpeedProvider) {
        // Settings first so both controllers can hold a reference.
        let settings = SettingsStore()
        self.settings = settings

        let service = TelemetryService(interval: settings.settings.refreshInterval.rawValue)
        // 5 minutes of history at 1 Hz = 300 samples per provider.
        service.add(cpu, storeCapacity: PopoverViewModel.historyWindow)
        service.add(fan, storeCapacity: PopoverViewModel.historyWindow)
        self.service = service

        // Push live changes to the user's `refreshInterval` setting into
        // the running timer. `removeDuplicates()` ensures we only re-arm
        // the timer when the interval itself changes — threshold or unit
        // changes leave the timer alone.
        settings.$settings
            .map(\.refreshInterval)
            .removeDuplicates()
            .sink { [weak service] interval in
                service?.setInterval(interval.rawValue)
            }
            .store(in: &cancellables)

        // Popover view model needs references to the providers, the
        // service, and the settings so it can read sample stores on
        // each render and surface the current display unit.
        let viewModel = PopoverViewModel(
            service: service,
            cpu: cpu,
            fan: fan,
            settings: settings
        )
        let popover = PopoverController(viewModel: viewModel)
        let menuBar = MenuBarController(
            service: service,
            cpu: cpu,
            settings: settings
        )

        // Click on the status item → toggle the popover.
        menuBar.onClick = { [weak popover] button in
            popover?.toggle(relativeTo: button)
        }

        // Each tick: redraw the menu bar; ask the popover to refresh itself.
        // `PopoverController.refresh()` is gated on visibility internally,
        // so this costs nothing when the popover is closed — the
        // per-tick view model rebuild only happens while the popover is
        // actually on screen and reading the snapshots.
        service.onUpdate = { [weak menuBar, weak popover] _ in
            menuBar?.render()
            popover?.refresh()
        }

        self.menuBar = menuBar
        self.popover = popover

        service.start()
    }
}
