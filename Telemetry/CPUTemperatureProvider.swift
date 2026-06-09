import Foundation
import SMCKit

/// Reads CPU temperature from one or more SMC SoC temperature keys.
///
/// On Apple Silicon, `Tp09` is the canonical aggregate; `Tp01` and `Tp05`
/// expose additional SoC zones on some machines. We probe all three at
/// init and report one `Metric` per available key.
///
/// The first available key (in the `tp09, tp01, tp05` order) is designated
/// the "primary" reading — its value is what the menu bar sparkline plots
/// and what the popover shows as the headline number.
final class CPUTemperatureProvider: TelemetryProvider {
    let name = "CPU Temperature"

    private struct Source {
        let key: FourCharCode
        let label: String
    }

    private let sources: [Source]
    private(set) var primaryLabel: String?

    init() async {
        // Probe order: primary first, then secondary zones.
        let candidates: [Source] = [
            .init(key: SMCKeys.tp09, label: "SoC"),
            .init(key: SMCKeys.tp01, label: "SoC Zone 0"),
            .init(key: SMCKeys.tp05, label: "SoC Zone 1"),
        ]
        var available: [Source] = []
        for source in candidates {
            if await (try? SMCKit.shared.isKeyFound(source.key)) == true {
                available.append(source)
            }
        }
        self.sources = available
        self.primaryLabel = available.first?.label

        let names = candidates.map { SMCKeys.name($0.key) }.joined(separator: ", ")
        if available.isEmpty {
            print("Specter: CPU temperature provider found no keys in [\(names)]")
        } else {
            let availableNames = available.map { "\(SMCKeys.name($0.key))=\($0.label)" }
                .joined(separator: ", ")
            print("Specter: CPU temperature provider active: \(availableNames)")
        }
    }

    var isAvailable: Bool { !sources.isEmpty }

    func sample() async -> [Metric] {
        var result: [Metric] = []
        for source in sources {
            do {
                let value: Float = try await SMCKit.shared.read(source.key)
                result.append(Metric(label: source.label, value: Double(value), unit: .celsius))
            } catch {
                // Quietly skip a single failed read; the menu bar will show
                // the most recent value and the popover will omit the row
                // for this tick.
                continue
            }
        }
        return result
    }
}
