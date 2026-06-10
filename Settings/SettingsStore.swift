import Foundation

/// Main-actor `ObservableObject` that wraps the persisted `Settings` and
/// republishes whenever one of *our* keys changes in `UserDefaults`.
///
/// We can't use SwiftUI's `@AppStorage` from `MenuBarController` (it's
/// not a view), so the menu bar reads `store.settings` on every render
/// to pick the right color. The SwiftUI popover uses `@AppStorage`
/// directly and writes to `UserDefaults` on every slider/picker change.
///
/// `UserDefaults.didChangeNotification` is the only signal we have that
/// any `@AppStorage` write happened, and it carries no useful `userInfo`.
/// The cheap path is: snapshot the current value, on every notification
/// re-read defaults, and only republish if the value actually changed.
/// That collapses bursts of unrelated notifications (writes from other
/// apps, system writes) into a single cheap `Equatable` comparison
/// in the common case, and lets live changes from the popover's
/// `@AppStorage` flow through to the menu bar and `TelemetryService`.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
        self.observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `self` is @MainActor-isolated; hop back to the main actor
            // to mutate `settings`.
            MainActor.assumeIsolated {
                guard let self else { return }
                let next = Self.load(from: self.defaults)
                if next != self.settings {
                    self.settings = next
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private static func load(from d: UserDefaults) -> Settings {
        Settings(
            greenYellowThreshold: d.object(forKey: SettingsKey.greenYellowThreshold) as? Double
                ?? Settings.default.greenYellowThreshold,
            yellowRedThreshold: d.object(forKey: SettingsKey.yellowRedThreshold) as? Double
                ?? Settings.default.yellowRedThreshold,
            unit: Settings.Unit(rawValue: d.string(forKey: SettingsKey.unit) ?? "")
                ?? Settings.default.unit,
            refreshInterval: Settings.RefreshInterval(
                rawValue: d.object(forKey: SettingsKey.refreshInterval) as? Double
                    ?? Settings.default.refreshInterval.rawValue
            ) ?? Settings.default.refreshInterval
        )
    }
}
