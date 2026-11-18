import Foundation

/// Mirrors `ps4-linux-launcher-app/linux-loader/include/LinuxBootConfig.h` and `LinuxBootConfigLite.cpp`.
public enum LinuxBootConfigLogic {
    public static let archGbMin = 50
    public static let archGbDefault = 100
    public static let archGbMax = 512

    public static let allowedVramMb: [Int] = [512, 1024, 2048, 4096]

    public struct Values: Equatable {
        public var vramMb: Int
        public var archGb: Int
        public var verboseBoot: Bool
        public var payload: String
        public var installTarget: String

        public init(
            vramMb: Int = 1024,
            archGb: Int = archGbDefault,
            verboseBoot: Bool = true,
            payload: String = "auto",
            installTarget: String = "internal_hdd"
        ) {
            self.vramMb = vramMb
            self.archGb = archGb
            self.verboseBoot = verboseBoot
            self.payload = payload
            self.installTarget = installTarget
        }
    }

    public static func clampArchGb(_ gb: Int) -> Int {
        min(archGbMax, max(archGbMin, gb))
    }

    public static func normalize(_ values: inout Values) {
        values.archGb = clampArchGb(values.archGb)
        if !allowedVramMb.contains(values.vramMb) {
            values.vramMb = values.vramMb < 768 ? 512 : 1024
        }
    }

    /// Same field subset as `LinuxBootConfigLite.cpp` (no nlohmann).
    public static func parseLiteJSON(_ raw: String) -> Values? {
        guard let vram = readIntField(raw, key: "vram_mb") else { return nil }
        guard let arch = readIntField(raw, key: "arch_gb") else { return nil }
        var v = Values(vramMb: vram, archGb: arch)
        if let vb = readBoolField(raw, key: "verbose_boot") {
            v.verboseBoot = vb
        }
        if let p = readQuotedField(raw, key: "payload") {
            v.payload = p
        }
        if let t = readQuotedField(raw, key: "install_target") {
            v.installTarget = t
        }
        normalize(&v)
        return v
    }

    public static func serializeLiteJSON(_ values: Values) -> String {
        var v = values
        normalize(&v)
        return """
        {
          "vram_mb": \(v.vramMb),
          "arch_gb": \(v.archGb),
          "verbose_boot": \(v.verboseBoot ? "true" : "false"),
          "payload": "\(v.payload)",
          "install_target": "\(v.installTarget)"
        }

        """
    }

    public static func syncInstallGbDefault() -> Int { archGbDefault }

    public static func syncInstallGbClamped(_ n: Int) -> Int {
        max(archGbMin, n)
    }

    private static func readIntField(_ raw: String, key: String) -> Int? {
        let needle = "\"\(key)\":"
        guard let range = raw.range(of: needle) else { return nil }
        var p = raw[range.upperBound...]
        while p.first == " " || p.first == "\t" { p = p.dropFirst() }
        let digits = p.prefix(while: { $0.isNumber || $0 == "-" })
        return Int(digits)
    }

    private static func readBoolField(_ raw: String, key: String) -> Bool? {
        let needle = "\"\(key)\":"
        guard let range = raw.range(of: needle) else { return nil }
        let tail = raw[range.upperBound...]
        if tail.hasPrefix("true") { return true }
        if tail.hasPrefix("false") { return false }
        return nil
    }

    private static func readQuotedField(_ raw: String, key: String) -> String? {
        let needle = "\"\(key)\":"
        guard let keyRange = raw.range(of: needle) else { return nil }
        guard let q1 = raw.range(of: "\"", range: keyRange.upperBound..<raw.endIndex) else { return nil }
        guard let q2 = raw.range(of: "\"", range: q1.upperBound..<raw.endIndex) else { return nil }
        return String(raw[q1.upperBound..<q2.lowerBound])
    }
}
