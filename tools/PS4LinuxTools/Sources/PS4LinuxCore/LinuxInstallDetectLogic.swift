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
    /// Linux ext2 superblock present in the partition image (not native PS4 UFS).
    public var archHasExt2: Bool

    public init(
        archImgBytes: Int64? = nil,
        installMeta: String? = nil,
        installStatus: String? = nil,
        archHasExt2: Bool = false
    ) {
        self.archImgBytes = archImgBytes
        self.installMeta = installMeta
        self.installStatus = installStatus
        self.archHasExt2 = archHasExt2
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
            var fromMarkers = LinuxInstallState()
            let meta = inputs.installMeta
            let status = inputs.installStatus
            var complete = false
            if let meta {
                if readMetaField(meta, key: "install_complete") == "1" {
                    complete = true
                }
                if let d = readMetaField(meta, key: "distro") {
                    fromMarkers.distro = d
                }
                if let gbStr = readMetaField(meta, key: "arch_gb"), let gb = Int(gbStr) {
                    fromMarkers.metaArchGb = gb
                }
            }
            if let status, installStatusIndicatesComplete(status) {
                complete = true
            }
            if complete {
                fromMarkers.level = .ready
                let showGb = fromMarkers.metaArchGb > 0 ? fromMarkers.metaArchGb : 100
                let distro = fromMarkers.distro.isEmpty ? "psxitarch" : fromMarkers.distro
                fromMarkers.summaryLine =
                    "Linux partition ready: \(distro) on internal HDD (\(showGb) GB) — boot OK (image not visible to Orbis app)"
                return fromMarkers
            }
            if meta != nil || status != nil {
                return LinuxInstallState(
                    level: .partial,
                    summaryLine: "Install meta on PS4 HDD but Linux partition file missing — run Setup new"
                )
            }
            return LinuxInstallState(summaryLine: "No Linux partition on PS4 HDD (Arch.img not on /user/home)")
        }

        var out = LinuxInstallState()
        out.archImgSizeGb = Int((archBytes + oneGb - 1) / oneGb)

        if archBytes < minArchBytesForPartial {
            out.level = .partial
            out.summaryLine = "Partial Linux partition (image too small — use Setup new)"
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

        if out.level != .ready, out.archImgSizeGb >= 50, inputs.archHasExt2 {
            out.level = .ready
        }

        if out.level != .ready {
            out.level = .partial
            if inputs.archHasExt2 {
                out.summaryLine = "Linux ext2 partition found — finish install or use Boot (not native PS4 storage)"
            } else if out.archImgSizeGb >= 10 {
                out.summaryLine =
                    "Linux partition file allocated — formatting/install not finished (Setup new to retry)"
            } else {
                out.summaryLine = "Partial Linux partition — use Setup new to wipe and retry"
            }
            return out
        }

        let showGb = out.metaArchGb > 0 ? out.metaArchGb : out.archImgSizeGb
        let distro = out.distro.isEmpty ? "psxitarch" : out.distro
        out.summaryLine =
            "Linux partition ready: \(distro) ext2 in Arch.img (\(showGb) GB) — separate from native PS4 — boot OK"
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
            || status.contains("install_complete=1")
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
