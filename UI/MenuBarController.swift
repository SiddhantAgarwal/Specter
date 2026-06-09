import AppKit
import QuartzCore

/// Owns the menu bar status item and renders the rounded numeric CPU
/// temperature, colored by the current threshold settings.
///
/// Color is applied via `attributedTitle` (NSAttributedString) — a plain
/// `String` title can't carry color attributes. The button's layer
/// (`wantsLayer = true`) is required for the `CATransition` fade to work.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let service: TelemetryService
    private let cpu: CPUTemperatureProvider
    private let settings: SettingsStore

    init(
        service: TelemetryService,
        cpu: CPUTemperatureProvider,
        settings: SettingsStore
    ) {
        // -1.0 = NSStatusItem.variableLength (item width fits its title)
        self.statusItem = NSStatusBar.system.statusItem(withLength: -1.0)
        self.service = service
        self.cpu = cpu
        self.settings = settings
        super.init()
        installClickHandler()
        // The button needs a layer-backed view for CATransition to work.
        statusItem.button?.wantsLayer = true
    }

    private func installClickHandler() {
        // Single click → popover toggle. We do this via the button's target/
        // action rather than `statusItem.button?.sendAction(...)` so the
        // PopoverController can swap the handler in cleanly.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
    }

    /// Set by AppDelegate after the PopoverController is built. Splitting
    /// the wiring this way avoids a retain cycle (MenuBarController does
    /// not own the popover).
    var onClick: ((NSStatusBarButton) -> Void)?

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        onClick?(sender)
    }

    // MARK: - Rendering

    /// Re-renders the status item title from the latest sample store data.
    /// Called by `TelemetryService.onUpdate` once per tick.
    func render() {
        guard let button = statusItem.button else { return }
        // CATransaction batching: one dirty mark per tick, no implicit
        // animation on the title change.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // CATransition produces the smooth fade between value/color changes.
        // We attach it directly to the button's layer (must be wantsLayer).
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.18
        button.layer?.add(transition, forKey: "titleFade")
        defer { CATransaction.commit() }

        guard cpu.isAvailable,
              let store = service.store(for: cpu),
              let primary = cpu.primaryLabel
        else {
            button.attributedTitle = NSAttributedString(string: "—°")
            return
        }

        guard let celsius = store.latest()?.first(where: { $0.label == primary })?.value
        else {
            button.attributedTitle = NSAttributedString(string: "—°")
            return
        }

        let unit = settings.settings.unit
        let displayValue = unit.convertFromCelsius(celsius)
        let bucket = settings.settings.bucket(forCelsius: celsius)
        let color = Self.nsColor(for: bucket)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font,
        ]
        button.attributedTitle = NSAttributedString(
            string: "\(Int(displayValue.rounded()))°",
            attributes: attributes
        )
    }

    private static func nsColor(for bucket: Settings.ColorBucket) -> NSColor {
        switch bucket {
        case .green: return NSColor.systemGreen
        case .yellow: return NSColor.systemYellow
        case .red: return NSColor.systemRed
        }
    }
}
