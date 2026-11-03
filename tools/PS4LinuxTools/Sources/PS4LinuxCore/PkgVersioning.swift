import Foundation

public struct PkgVersioning {
    public struct BumpResult: Equatable {
        public var display: String
        public var sonyAppVer: String
        public var masterVersion: String
        public var buildLabel: String
    }

    public static func sonyAppVer(buildNum: Int) -> String {
        String(format: "%02d.%02d", buildNum / 100, buildNum % 100)
    }

    public static func masterVersion(buildNum: Int) -> String {
        String(format: "01.%d", buildNum)
    }

    public static func versionedPkgFileName(display: String, buildLabel: String, sonyAppVer: String) -> String {
        let appDigits = sonyAppVer.replacingOccurrences(of: ".", with: "")
        return "PS4-Linux-v\(display)-b\(buildLabel)-APP\(appDigits).pkg"
    }

    /// Parses PKG_VERSION + PKG_BUILD_NUM and optionally bumps patch + build counter.
    public static func bump(
        displayRaw: String,
        buildNumRaw: String?,
        bump: Bool
    ) -> BumpResult {
        var parts = displayRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .compactMap { Int($0) }
        while parts.count < 3 { parts.append(0) }
        if parts[0] == 0 && parts[1] < 7 {
            parts = [0, 7, 0]
        }

        var buildNum = 70
        if let buildNumRaw,
           let parsed = Int(buildNumRaw.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsed >= 70 {
            buildNum = parsed
        }

        if bump {
            parts[2] += 1
            buildNum += 1
        } else if buildNum < 70 {
            buildNum = 70
        }

        let display = "\(parts[0]).\(parts[1]).\(parts[2])"
        let buildLabel = String(buildNum)
        let appVer = sonyAppVer(buildNum: buildNum)
        let master = masterVersion(buildNum: buildNum)
        return BumpResult(display: display, sonyAppVer: appVer, masterVersion: master, buildLabel: buildLabel)
    }

    public static func appVerDiffersFromMaster(_ appVer: String, _ master: String) -> Bool {
        appVer != master
    }

    public static func appVerFitsParamSfo(_ appVer: String) -> Bool {
        appVer.count <= 7 && appVer.contains(".")
    }
}
