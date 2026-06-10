import AppKit
import SwiftUI

/// Custom `NSView` that always refuses first-responder status.
/// Returned from `FixedSizeHostingController.view`. Keeps the
/// popover's NSPanel from being promoted to key — a prerequisite
/// for `.transient` to dismiss on outside click. (`NSPopover` is
/// backed by an `NSPanel` whose `becomesKeyOnlyIfNeeded` defaults
/// to true; once the popover's hosted SwiftUI view accepts first
/// responder — which SwiftUI does by default for accessibility/
/// hit-testing — the panel becomes key, and `.transient` then
/// considers clicks "inside" the key window and stops dismissing
/// on outside clicks.)
private final class NonKeyView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Custom `NSHostingController` subclass that:
/// 1. Pins `preferredContentSize` to a fixed value (prevents
///    `NSPopover` from resizing itself mid-show based on SwiftUI's
///    intrinsic size — produces the "top chopped" effect on macOS
///    26.5 when the popover's rounded-corner insets aren't
///    accounted for).
/// 2. Re-parents the SwiftUI hosting view into a `NonKeyView`
///    container so the popover's NSPanel does not become key.
///
/// Without (2), the popover's window becomes key the moment the
/// SwiftUI content is installed, and `.transient` stops working.
@MainActor
final class FixedSizeHostingController<Content: View>: NSHostingController<Content> {
    private let fixedSize: NSSize

    init(rootView: Content, size: NSSize) {
        self.fixedSize = size
        super.init(rootView: rootView)
        self.preferredContentSize = size
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        // Set up the SwiftUI hosting view first so `self.view`
        // references it (we'll re-parent it momentarily).
        super.loadView()
        let swiftUIView = self.view
        swiftUIView.frame = NSRect(origin: .zero, size: fixedSize)
        // Wrap the SwiftUI view in a non-first-responder container.
        // The container becomes `self.view`; the SwiftUI view is
        // its sole subview, filling its bounds.
        let container = NonKeyView(frame: NSRect(origin: .zero, size: fixedSize))
        swiftUIView.removeFromSuperview()
        swiftUIView.frame = container.bounds
        swiftUIView.autoresizingMask = [.width, .height]
        container.addSubview(swiftUIView)
        self.view = container
    }

    override var preferredContentSize: NSSize {
        get { fixedSize }
        set { /* ignore — popover must stay at fixed size */ }
    }
}

/// Owns the `NSPopover` and the click-toggle behavior. Hosts a SwiftUI
/// `PopoverView` via `FixedSizeHostingController`.
///
/// The popover is `transient` *and* guarded by an explicit
/// outside-click monitor. On macOS 26, `NSPopover` backed by an
/// `NSHostingController` is often promoted to key-window status by
/// AppKit (likely because SwiftUI's hosting view needs first-responder
/// for text fields, hit-testing, etc.). Once the popover is key,
/// `.transient` stops dismissing on outside clicks — AppKit considers
/// the click to be inside the key window's "interactive area." The
/// mouse monitor is the belt-and-braces fix: even if `.transient`
/// breaks, we still close the popover when the user clicks anywhere
/// outside it.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let viewModel: PopoverViewModel

    /// Pinned popover dimensions. Width 280 = the design width set on
    /// the SwiftUI view's `.frame(width: 280)`. Height 470 = enough for
    /// the full layout (CPU + chart + FAN + divider + settings + refresh
    /// row + quit) with comfortable margins, so neither the top nor the
    /// bottom row is clipped. If you add a new section to `PopoverView`,
    /// bump this.
    private static let contentSize = NSSize(width: 280, height: 470)

    /// True between `popoverWillShow` and `popoverDidClose`. Used to
    /// gate per-tick re-renders so the SwiftUI view isn't asked to
    /// re-evaluate its body while the popover is in the middle of
    /// AppKit's first-show layout pass. The
    /// "It's not legal to call -layoutSubtreeIfNeeded on a view which
    /// is already being laid out" warning fires when a 1 Hz tick
    /// triggers a SwiftUI body re-evaluation during the popover's
    /// initial `viewWillLayout` → `viewDidLayout` cycle.
    private var isPopoverVisible = false

    /// Mouse-down monitor that closes the popover on outside clicks.
    /// Installed in `popoverDidShow`, removed in `popoverDidClose` so
    /// we don't pay for it when the popover isn't on screen.
    private var outsideClickMonitor: Any?

    /// Global counterpart of `outsideClickMonitor`. Global monitors
    /// see clicks outside our app (desktop, other apps), which local
    /// monitors cannot.
    private var globalClickMonitor: Any?

    /// Weak reference to the status item's button. Set in
    /// `toggle(relativeTo:)` when the popover is shown. The
    /// outside-click monitor uses this to distinguish "user clicked
    /// the status item to toggle the popover" (handled by the
    /// button's own target/action) from "user clicked elsewhere
    /// to dismiss" (which the monitor must handle).
    private weak var statusButton: NSStatusBarButton?

    init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
        super.init()
        popover.behavior = .transient
        // Disable the popover's show/hide animation. While the popover
        // is mid-animation, AppKit runs a layout pass on its content
        // view; if a 1 Hz tick fires during that pass and re-renders
        // the SwiftUI content, the `layoutSubtreeIfNeeded` recursion
        // guard trips and logs "It's not legal to call
        // -layoutSubtreeIfNeeded on a view which is already being laid
        // out." The animation is cosmetic and not worth that.
        popover.animates = false
        popover.contentSize = Self.contentSize
        popover.contentViewController = FixedSizeHostingController(
            rootView: PopoverView(viewModel: viewModel),
            size: Self.contentSize
        )
        popover.delegate = self
    }

    deinit {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Toggle visibility. Called by `MenuBarController` when the status
    /// item is clicked. Anchors the popover to the bottom edge of the
    /// status button so it hangs below the menu bar like every other
    /// macOS status item popover.
    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Stash the status button so the outside-click monitor
            // can tell "click on the status item" (which is a toggle
            // handled by AppKit) from "click anywhere else" (which
            // should dismiss the popover). There's no public API to
            // enumerate status items by window, so we hold a weak
            // reference to the one our menu bar uses.
            statusButton = button
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Called by `TelemetryService.onUpdate` once per tick. We only
    /// re-render the SwiftUI view if the popover is currently visible;
    /// otherwise we'd be mutating `@Published` properties on the view
    /// model and triggering SwiftUI invalidation work that has no
    /// observable effect (and can re-enter AppKit's layout system
    /// when the popover is being shown).
    func refresh() {
        guard isPopoverVisible else { return }
        viewModel.tick()
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        // Mark visible *before* the layout pass so `refresh()` can run
        // if a tick lands here.
        isPopoverVisible = true
        // First tick on open so the popover shows fresh data even if
        // the user opens it just after a tick has already fired.
        viewModel.tick()
    }

    func popoverDidShow(_ notification: Notification) {
        // Install the outside-click monitor *after* the popover is on
        // screen. If we install it in `popoverWillShow`, the popover's
        // own show-time mouse events can race with the monitor and
        // cause it to dismiss immediately.
        installOutsideClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        isPopoverVisible = false
        removeOutsideClickMonitor()
    }

    // MARK: - Outside-click dismissal

    /// Install event monitors that close the popover on outside clicks.
    /// This is the standard pattern for `NSStatusItem` popovers on
    /// recent macOS, because `.transient` is unreliable once the
    /// popover becomes key (which AppKit does automatically for
    /// `NSHostingController`-backed content).
    ///
    /// Two monitors are installed:
    /// - **Global** (`addGlobalMonitorForEvents`): catches clicks
    ///   outside our app entirely (desktop, another app, the
    ///   menubar's empty area). Local monitors can't see these.
    /// - **Local** (`addLocalMonitorForEvents`): catches clicks that
    ///   are inside our app but outside the popover's window. We
    ///   forward those events after closing the popover so the
    ///   underlying view still receives the click.
    ///
    /// The status-item button itself is excluded: re-clicking the
    /// status item toggles the popover (handled by the button's
    /// target/action), so we must not let the monitor close the
    /// popover underneath the toggle.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()

        // Local monitor: clicks inside our app but outside the popover.
        // We return the event so the click is delivered normally; we
        // just close the popover first.
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            if self.isClickOnStatusItem(event) { return event }
            if self.isClickInsidePopover(event) { return event }
            DispatchQueue.main.async { [weak self] in
                self?.popover.performClose(nil)
            }
            return event
        }
        outsideClickMonitor = local

        // Global monitor: clicks outside our app. Global monitors
        // cannot return the event (the API requires returning nil),
        // which is fine — we just need to observe and close.
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            guard self.popover.isShown else { return }
            DispatchQueue.main.async { [weak self] in
                self?.popover.performClose(nil)
            }
        }
        globalClickMonitor = global
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    /// True if `event` happened on the status-item button. Re-clicking
    /// the button is a toggle, handled by the button's target/action —
    /// the monitor must not close the popover out from under it.
    private func isClickOnStatusItem(_ event: NSEvent) -> Bool {
        guard let statusWindow = statusButton?.window else { return false }
        return event.window === statusWindow
    }

    /// True if `event` happened inside the popover's content window.
    private func isClickInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else {
            return false
        }
        return event.window === popoverWindow
    }
}
