import Foundation

/// Fixed-size ring buffer of metric snapshots from a single provider.
///
/// One snapshot per polling tick. Used by the menu bar controller (latest
/// reading only) and the popover chart (recent window for the history line).
///
/// Backed by a preallocated `[Metric?]` with a write head and a fill count,
/// so `append` is O(1) and `recent(_:)` walks the live entries in place —
/// no `removeFirst` slice copies, no per-call array allocations on the
/// 1 Hz hot path.
///
/// Thread-safety: this type is main-actor-only. `TelemetryService` ticks on
/// the main queue; both the menu bar and popover read on the main queue.
@MainActor
final class SampleStore {
    private var storage: [[Metric]]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        // Pre-fill with empty snapshots so `storage[head]` is always safe
        // to write and `latest()` can return a non-optional value.
        self.storage = Array(repeating: [Metric](), count: capacity)
    }

    func append(_ snapshot: [Metric]) {
        storage[head] = snapshot
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// The most recent snapshot, or `nil` if no samples have been taken.
    func latest() -> [Metric]? {
        guard count > 0 else { return nil }
        let idx = (head - 1 + capacity) % capacity
        return storage[idx]
    }

    /// The last `n` snapshots in chronological order. Returns whatever is
    /// available if the buffer has fewer than `n` entries.
    func recent(_ n: Int) -> [[Metric]] {
        guard n > 0, count > 0 else { return [] }
        let take = min(n, count)
        var out: [[Metric]] = []
        out.reserveCapacity(take)
        // Oldest live entry sits at (head - count) mod capacity.
        let start = (head - count + capacity) % capacity
        for i in 0..<take {
            out.append(storage[(start + i) % capacity])
        }
        return out
    }

    /// Convenience: the `n` most-recent values of a metric with a given
    /// label. Used by the menu bar sparkline.
    func values(forLabel label: String, last n: Int) -> [Double] {
        let snapshots = recent(n)
        return snapshots.compactMap { snapshot in
            snapshot.first(where: { $0.label == label })?.value
        }
    }

    /// Build the per-label history the popover view needs in a single
    /// walk over the ring. Returns one `(label, values)` pair per label
    /// that appears in the recent window, sorted by label for stable
    /// ordering. `values` are in chronological order (oldest first).
    ///
    /// This replaces the previous code path that called `recent(_:)` once
    /// and then `values(forLabel:)` per label — the latter internally
    /// re-walked the buffer. For 300 samples × N labels that was several
    /// full scans per popover tick.
    func snapshotHistory(maxSamples n: Int) -> [(label: String, values: [Double])] {
        guard n > 0, count > 0 else { return [] }
        let take = min(n, count)
        let start = (head - count + capacity) % capacity
        var series: [String: [Double]] = [:]
        for i in 0..<take {
            for metric in storage[(start + i) % capacity] {
                series[metric.label, default: []].append(metric.value)
            }
        }
        return series.keys.sorted().map { ($0, series[$0] ?? []) }
    }

    var isEmpty: Bool { count == 0 }
}
