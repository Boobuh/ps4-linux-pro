import Foundation

/// FTP launch validation — empty logs after latest PKG install = CE-30008-1 / CE-41839-5 on hardware.
public enum ConsoleLaunchE2E {
    public static let defaultLogPaths = [
        "/data/pkg/ps4-linux-app.log",
        "/data/linux/boot/ps4-linux-last-run.txt",
        "/data/linux/boot/ps4-linux-app.log",
        "/user/app/CSTP00003/ps4-linux-app.log",
        "/user/data/ps4-linux-app.log",
    ]

    /// When `PS4_LINUX_E2E_STRICT` is unset, defaults to **true** (fail CI/agent if console is up but app never logged).
    public static var strictEmptyLogFails: Bool {
        let env = ProcessInfo.processInfo.environment["PS4_LINUX_E2E_STRICT"]?.lowercased()
        if env == "0" || env == "false" || env == "no" { return false }
        return true
    }

    public static func bootLogIndicatesLaunch(_ body: String) -> Bool {
        body.contains("RUN START") || body.contains("unified OpenOrbis eboot")
    }

    /// Compare Mac build artifact to console `app.json` install name (from console-cycle).
    public static func validateLaunchAfterInstall(
        macLatestPkgFileName: String?,
        consoleInstalledPkgFileName: String?,
        combinedBootLog: String
    ) -> [String] {
        var errors: [String] = []
        guard strictEmptyLogFails else { return errors }

        guard let mac = macLatestPkgFileName, mac.hasPrefix("PS4-Linux-v"), mac.hasSuffix(".pkg") else {
            return errors
        }
        guard let installed = consoleInstalledPkgFileName,
              installed.hasPrefix("PS4-Linux-v"), installed.hasSuffix(".pkg") else {
            return errors
        }

        if installed != mac {
            errors.append(
                "E2E: console has \(installed) but Mac latest is \(mac) — install Mac latest then launch once"
            )
            return errors
        }

        if combinedBootLog.isEmpty {
            errors.append(
                "E2E: \(installed) installed but all boot logs empty — CE-30008-1 / CE-41839-5 (kernel rejects SELF before BootTrace; not a truncated-PKG case)"
            )
            return errors
        }

        if !bootLogIndicatesLaunch(combinedBootLog) {
            errors.append("E2E: logs present but missing RUN START / unified eboot marker after install")
        }

        errors.append(contentsOf: PkgLayoutGuard.validateBootLogContent(combinedBootLog, expectedVersionPrefix: nil))
        return errors
    }
}
