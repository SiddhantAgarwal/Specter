import Foundation

/// Fixed-size ring buffer of metric snapshots from a single provider.
///
/// One snapshot per polling tick. Used by the menu bar controller (last
/// ~12 samples for the sparkline) and the popover chart (last 60 samples).
///
/// Thread-safety: this type is main-actor-only. `TelemetryService` ticks on
/// the main queue; both the menu bar and popover read on the main queue.
@MainActor
final class SampleStore {
    private var buffer: [[Metric]] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    func append(_ snapshot: [Metric]) {
        buffer.append(snapshot)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    /// The most recent snapshot, or `nil` if no samples have been taken.
    func latest() -> [Metric]? {
        buffer.last
    }

    /// The last `n` snapshots in chronological order. Returns whatever is
    /// available if the buffer has fewer than `n` entries.
    func recent(_ n: Int) -> [[Metric]] {
        guard n > 0, !buffer.isEmpty else { return [] }
        let start = max(0, buffer.count - n)
        return Array(buffer[start..<buffer.count])
    }

    /// Convenience: the `n` most-recent values of a metric with a given
    /// label. Used by the menu bar sparkline.
    func values(forLabel label: String, last n: Int) -> [Double] {
        let snapshots = recent(n)
        return snapshots.compactMap { snapshot in
            snapshot.first(where: { $0.label == label })?.value
        }
    }

    var isEmpty: Bool { buffer.isEmpty }
}
