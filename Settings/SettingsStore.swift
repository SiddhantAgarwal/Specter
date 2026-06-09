import Foundation
import Combine

/// Main-actor `ObservableObject` that wraps the persisted `Settings` and
/// republishes on any UserDefaults change.
///
/// We can't use SwiftUI's `@AppStorage` from `MenuBarController` (it's
/// not a view), so the menu bar reads `store.settings` on every render
/// to pick the right color. The SwiftUI popover uses `@AppStorage`
/// directly, and its writes trigger `UserDefaults.didChangeNotification`,
/// which this store catches and republishes — keeping menu bar and
/// popover in sync without a manual wiring.
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
                ?? Settings.default.unit
        )
    }
}
