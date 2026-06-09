import AppKit

/// Pure AppKit entry point. The SwiftUI `App` lifecycle was triggering a
/// double-registration with macOS's LinkD service hub on Xcode 26.5 / macOS
/// 26.5 (`@NSApplicationDelegateAdaptor` + `App` body both register), which
/// surfaced as "Unable to re-register with Process Instance Registry" and a
/// cascading `layoutSubtreeIfNeeded` recursion warning. Bypassing the SwiftUI
/// lifecycle entirely removes the duplicate handshake.
@main
enum SpecterAppMain {
    static func main() {
        let app = NSApplication.shared
        // The 50ms startup delay below gives AppKit's process registry
        // time to settle before the run loop starts, silencing the
        // "task_name_for_pid" / "os/kern) failure (0x5)" warning that
        // otherwise races at first launch on Xcode 26.5 / macOS 26.5.
        Thread.sleep(forTimeInterval: 0.05)
        // `AppDelegate` is @MainActor-isolated; the entry point runs on
        // the main thread, so we explicitly assume the actor.
        MainActor.assumeIsolated {
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory) // no Dock icon; matches LSUIElement
        }
        app.run()
    }
}
