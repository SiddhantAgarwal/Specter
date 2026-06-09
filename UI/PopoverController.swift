import AppKit
import SwiftUI

/// Custom `NSHostingController` subclass that pins `preferredContentSize`
/// to a fixed value and prevents SwiftUI from re-reporting a different
/// size mid-show. Without this, `NSHostingController` updates
/// `preferredContentSize` to match the SwiftUI view's intrinsic size on
/// every layout pass; `NSPopover` reads that and resizes itself
/// accordingly — sometimes with a frame that doesn't include the
/// rounded-corner insets, which is what produces the "top chopped"
/// effect on macOS 26.5.
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
        super.loadView()
        // Pin the view's frame to our fixed size so the SwiftUI layout
        // pass can't grow or shrink the popover's content view.
        view.frame = NSRect(origin: .zero, size: fixedSize)
    }

    override var preferredContentSize: NSSize {
        get { fixedSize }
        set { /* ignore — popover must stay at fixed size */ }
    }
}

/// Owns the `NSPopover` and the click-toggle behavior. Hosts a SwiftUI
/// `PopoverView` via `FixedSizeHostingController`.
///
/// The popover is `transient` — clicking outside the popover closes it,
/// which is what users expect from a status item popover.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let viewModel: PopoverViewModel

    /// Pinned popover dimensions. Width 280 = the design width set on
    /// the SwiftUI view's `.frame(width: 280)`. Height 440 = enough for
    /// the full layout (CPU + chart + FAN + divider + settings + quit)
    /// with comfortable margins, so neither the top nor the bottom row
    /// is clipped. If you add a new section to `PopoverView`, bump this.
    private static let contentSize = NSSize(width: 280, height: 440)

    /// True between `popoverWillShow` and `popoverDidClose`. Used to
    /// gate per-tick re-renders so the SwiftUI view isn't asked to
    /// re-evaluate its body while the popover is in the middle of
    /// AppKit's first-show layout pass. The
    /// "It's not legal to call -layoutSubtreeIfNeeded on a view which
    /// is already being laid out" warning fires when a 1 Hz tick
    /// triggers a SwiftUI body re-evaluation during the popover's
    /// initial `viewWillLayout` → `viewDidLayout` cycle.
    private var isPopoverVisible = false

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

    /// Toggle visibility. Called by `MenuBarController` when the status
    /// item is clicked. Anchors the popover to the bottom edge of the
    /// status button so it hangs below the menu bar like every other
    /// macOS status item popover.
    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
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

    func popoverDidClose(_ notification: Notification) {
        isPopoverVisible = false
    }
}
