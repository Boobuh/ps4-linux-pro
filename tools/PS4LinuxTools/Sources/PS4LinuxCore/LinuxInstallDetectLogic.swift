import Foundation

/// Mirrors `linux-loader/src/LinuxInstallDetect.cpp`.
public enum LinuxInstallLevel: Equatable {
    case none
    case partial
    case ready
}

public struct LinuxInstallState: Equatable {
    public var level: LinuxInstallLevel
    public var archImgSizeGb: Int
    public var metaArchGb: Int
    public var distro: String
    public var summaryLine: String

    public init(
        level: LinuxInstallLevel = .none,
        archImgSizeGb: Int = 0,
        metaArchGb: Int = 0,
        distro: String = "",
        summaryLine: String = ""
    ) {
        self.level = level
        self.archImgSizeGb = archImgSizeGb
        self.metaArchGb = metaArchGb
        self.distro = distro
        self.summaryLine = summaryLine
    }

    public var isReady: Bool { level == .ready }
    public var isPartial: Bool { level == .partial }
}

public struct LinuxInstallInputs: Equatable {
    /// `nil` = Arch.img missing.
    public var archImgBytes: Int64?
    public var installMeta: String?
    public var installStatus: String?

    public init(archImgBytes: Int64? = nil, installMeta: String? = nil, installStatus: String? = nil) {
        self.archImgBytes = archImgBytes
        self.installMeta = installMeta
        self.installStatus = installStatus
    }
}

public struct LinuxInstallPaths: Equatable {
    public var archImg: URL
    public var installMeta: URL
    public var installStatus: URL

    public init(archImg: URL, installMeta: URL, installStatus: URL) {
        self.archImg = archImg
        self.installMeta = installMeta
        self.installStatus = installStatus
    }
}

public enum LinuxInstallDetectLogic {
    private static let oneGb: Int64 = 1024 * 1024 * 1024
    private static let minArchBytesForPartial: Int64 = 256 * 1024 * 1024

    public static func detect(inputs: LinuxInstallInputs) -> LinuxInstallState {
        guard let archBytes = inputs.archImgBytes, archBytes >= 0 else {
            return LinuxInstallState(summaryLine: "No Linux on internal HDD (Arch.img missing)")
        }

        var out = LinuxInstallState()
        out.archImgSizeGb = Int((archBytes + oneGb - 1) / oneGb)

        if archBytes < minArchBytesForPartial {
            out.level = .partial
            out.summaryLine = "Partial Linux install (Arch.img too small — use Setup new)"
            return out
        }

        if let meta = inputs.installMeta {
            if let d = readMetaField(meta, key: "distro") {
                out.distro = d
            }
            if let gbStr = readMetaField(meta, key: "arch_gb"), let gb = Int(gbStr) {
                out.metaArchGb = gb
            }
            if readMetaField(meta, key: "install_complete") == "1" {
                out.level = .ready
            }
        }

        if let status = inputs.installStatus, installStatusIndicatesComplete(status) {
            out.level = .ready
        }

        if out.level != .ready, out.archImgSizeGb >= 50 {
            out.level = .ready
        }

        if out.level != .ready {
            out.level = .partial
            out.summaryLine = "Partial Linux install — use Setup new to wipe and retry"
            return out
        }

        let showGb = out.metaArchGb > 0 ? out.metaArchGb : out.archImgSizeGb
        let distro = out.distro.isEmpty ? "psxitarch" : out.distro
        out.summaryLine = "Installed: \(distro) on internal HDD (\(showGb) GB partition)"
        return out
    }

    public static func detect(paths: LinuxInstallPaths, fileManager: FileManager = .default) -> LinuxInstallState {
        let archBytes: Int64?
        if fileManager.fileExists(atPath: paths.archImg.path),
           let attrs = try? fileManager.attributesOfItem(atPath: paths.archImg.path),
           let size = attrs[.size] as? Int64 {
            archBytes = size
        } else {
            archBytes = nil
        }
        let meta = readText(paths.installMeta, fileManager: fileManager)
        let status = readText(paths.installStatus, fileManager: fileManager)
        return detect(inputs: LinuxInstallInputs(archImgBytes: archBytes, installMeta: meta, installStatus: status))
    }

    @discardableResult
    public static func wipe(paths: LinuxInstallPaths, fileManager: FileManager = .default) throws -> Bool {
        var removedAny = false
        for url in [paths.archImg, paths.installStatus, paths.installMeta] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
            removedAny = true
        }
        return removedAny
    }

    public static func installStatusIndicatesComplete(_ status: String) -> Bool {
        status.contains("Step 3/3 done")
            || status.contains("extract finished")
            || status.contains("switch_root")
    }

    public static func readMetaField(_ raw: String, key: String) -> String? {
        let needle = "\(key)="
        guard let range = raw.range(of: needle) else { return nil }
        let start = range.upperBound
        let end = raw[start...].firstIndex(of: "\n") ?? raw.endIndex
        let value = String(raw[start..<end])
        return value.isEmpty ? nil : value
    }

    private static func readText(_ url: URL, fileManager: FileManager) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
