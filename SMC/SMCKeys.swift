import Foundation
import SMCKit

/// Shared SMC key constants used by all providers.
///
/// `FourCharCode` is a big-endian UInt32; the `FourCharCode("TC0P")` literal
/// form does the 4-character → UInt32 conversion for us. Order matters for
/// `CPUTemperatureProvider`: the first key found is the "primary" reading
/// used for the menu bar sparkline.
///
/// Reference: https://github.com/tigattack/macOS-hardware-stats/blob/main/KnownSMCKeys.md
enum SMCKeys {
    // CPU temperature zones. The Apple-Silicon SoC exposes a small set of
    // these; Intel Macs use the `TC0*` family.
    static let tp09: FourCharCode = "Tp09"  // primary SoC proximity (M-series)
    static let tp01: FourCharCode = "Tp01"
    static let tp05: FourCharCode = "Tp05"

    // Fan actual RPM. Mac Pros can have up to 4; consumer M-series often
    // has 0 or 1; MacBook Air has none.
    static let f0ac: FourCharCode = "F0Ac"
    static let f1ac: FourCharCode = "F1Ac"
    static let f2ac: FourCharCode = "F2Ac"
    static let f3ac: FourCharCode = "F3Ac"

    /// Pretty-print a keycode back to its 4-character string form.
    /// Useful for log lines.
    static func name(_ code: FourCharCode) -> String {
        var big = code.bigEndian
        let bytes = withUnsafeBytes(of: &big) { Array($0) }
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", code)
    }
}
