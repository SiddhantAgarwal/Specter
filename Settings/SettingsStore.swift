import Foundation

/// Main-actor `ObservableObject` that wraps the persisted `Settings` and
/// republishes on any UserDefaults change.
///
/// We can't use SwiftUI's `@AppStorage` from `MenuBarController` (it's
/// not a view), so the menu bar reads `store.settings` on every render
/// to pick the right color. The SwiftUI popover uses `@AppStorage`
/// directly and writes to `UserDefaults` on every slider/picker change.
/// The menu bar picks up those writes on its next 1 Hz render — that's
/// good enough, and avoids a `UserDefaults.didChangeNotification` observer
/// that would otherwise fire (and trigger a re-read of every key in the
/// process) on writes from *any* app on the system, since the
/// notification carries no useful `userInfo` to filter on.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    private static func load(from d: UserDefaults) -> Settings {
        Settings(
            greenYellowThreshold: d.object(forKey: SettingsKey.greenYellowThreshold) as? Double
                ?? Settings.default.greenYellowThreshold,
            yellowRedThreshold: d.object(forKey: SettingsKey.yellowRedThreshold) as? Double
                ?? Settings.default.yellowRedThreshold,
            unit: Settings.Unit(rawValue: d.string(forKey: SettingsKey.unit) ?? "")
                ?? Settings.default.unit
        )
    }
}
