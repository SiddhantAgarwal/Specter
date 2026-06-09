import Foundation
import SMCKit

/// Reads fan RPM from the SMC. Probes `F0Ac`–`F3Ac` at init; if none are
/// present (e.g. MacBook Air, fanless M-series machines), `isAvailable`
/// is `false` and the popover hides the section entirely.
final class FanSpeedProvider: TelemetryProvider {
    let name = "Fan Speed"

    private struct Source {
        let key: FourCharCode
        let label: String
    }

    private let sources: [Source]

    init() async {
        let candidates: [Source] = [
            .init(key: SMCKeys.f0ac, label: "Fan 0"),
            .init(key: SMCKeys.f1ac, label: "Fan 1"),
            .init(key: SMCKeys.f2ac, label: "Fan 2"),
            .init(key: SMCKeys.f3ac, label: "Fan 3"),
        ]
        var available: [Source] = []
        for source in candidates {
            if await (try? SMCKit.shared.isKeyFound(source.key)) == true {
                available.append(source)
            }
        }
        self.sources = available

        if available.isEmpty {
            print("Specter: fan provider found no keys (fanless machine or no active cooling)")
        } else {
            let names = available.map { "\(SMCKeys.name($0.key))=\($0.label)" }
                .joined(separator: ", ")
            print("Specter: fan provider active: \(names)")
        }
    }

    var isAvailable: Bool { !sources.isEmpty }

    func sample() async -> [Metric] {
        var result: [Metric] = []
        for source in sources {
            do {
                // SMC encodes fan RPM as a UInt16 on most Macs.
                let rpm: UInt16 = try await SMCKit.shared.read(source.key)
                result.append(Metric(label: source.label, value: Double(rpm), unit: .rpm))
            } catch {
                continue
            }
        }
        return result
    }
}
