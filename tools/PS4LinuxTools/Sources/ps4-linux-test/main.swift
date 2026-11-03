import Foundation
import PS4LinuxCore

@main
struct PS4LinuxTestRunner {
    static func main() {
        var failed = 0
        let repo = RepoPaths.repoRoot(fromFile: #filePath)
        let loader = RepoPaths.loaderDir(repo: repo)

        print("=== PS4 Linux test runner ===\n")

        print("--- Unit (PS4LinuxCore via swift test) ---")
        let unit = runSwiftTest(packageDir: repo.appendingPathComponent("tools/PS4LinuxTools"))
        if unit != 0 { failed += 1 }

        print("\n--- Integration (repo + built PKG metadata) ---")
        failed += runIntegration(repo: repo, loader: loader)

        print("\n--- End-to-end (GoldHEN FTP smoke, optional) ---")
        failed += runE2E(repo: repo)

        if failed > 0 {
            fputs("\n\(failed) test stage(s) failed.\n", stderr)
            exit(1)
        }
        print("\nAll stages passed.")
    }

    static func runSwiftTest(packageDir: URL) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        task.arguments = ["test", "--package-path", packageDir.path]
        task.currentDirectoryURL = packageDir
        task.standardOutput = FileHandle.standardOutput
        task.standardError = FileHandle.standardError
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            fputs("swift test failed: \(error)\n", stderr)
            return 1
        }
    }

    static func runIntegration(repo: URL, loader: URL) -> Int {
        var errors: [String] = []

        let assets = loader.appendingPathComponent("assets")
        errors.append(contentsOf: LanguageAssetPaths.validateBundledAssets(in: assets))

        let makefile = loader.appendingPathComponent("Makefile")
        if let mk = try? String(contentsOf: makefile, encoding: .utf8) {
            for needle in ["BootTrace", "CSTP00002", "guest.elf", "ChainLauncher"] {
                if !mk.contains(needle) {
                    errors.append("Makefile missing \(needle)")
                }
            }
        } else {
            errors.append("Missing linux-loader/Makefile")
        }

        for src in ["src/BootTrace.c", "src/ChainLauncher.c", "include/BootTrace.h"] {
            if !FileManager.default.fileExists(atPath: loader.appendingPathComponent(src).path) {
                errors.append("Missing \(src)")
            }
        }

        let pkgTool = RepoPaths.pkgTool(repo: repo)
        let versioned = (try? FileManager.default.contentsOfDirectory(at: loader, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("PS4-Linux-v") && $0.pathExtension == "pkg" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first

        if let versioned, FileManager.default.fileExists(atPath: pkgTool.path) {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("ps4linux-pkg-test", isDirectory: true)
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            do {
                let sfo = try PkgInspector.extractParamSfo(from: versioned, pkgTool: pkgTool, workDir: work)
                let out = try PkgInspector.runPkgTool(pkgTool, args: ["sfo_listentries", sfo.path])
                let fields = PkgInspector.parseSfoListentries(out)
                if let buildFile = try? String(contentsOf: loader.appendingPathComponent("PKG_BUILD_NUM"), encoding: .utf8),
                   let buildNum = Int(buildFile.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let expectedApp = PkgVersioning.sonyAppVer(buildNum: buildNum)
                    let expectedMaster = PkgVersioning.masterVersion(buildNum: buildNum)
                    errors.append(contentsOf: PkgInspector.validateParam(
                        fields: fields, expectedAppVer: expectedApp, expectedMaster: expectedMaster
                    ))
                }
            } catch {
                errors.append("PKG param inspect: \(error.localizedDescription)")
            }
        } else {
            print("  (skip PKG param test — build PS4-Linux-v*.pkg first or install toolchain)")
        }

        for e in errors {
            fputs("  FAIL: \(e)\n", stderr)
        }
        if errors.isEmpty {
            print("  Integration OK")
        }
        return errors.isEmpty ? 0 : 1
    }

    static func runE2E(repo: URL) -> Int {
        let host = ProcessInfo.processInfo.environment["PS4_HOST"] ?? "10.0.1.7"
        let port = ProcessInfo.processInfo.environment["PS4_PORT"] ?? "2121"
        var errors: [String] = []

        guard ftpReachable(host: host, port: port) else {
            print("  (skip E2E — FTP \(host):\(port) unreachable; set PS4_HOST to run)")
            return 0
        }

        let list = ftpList(host: host, port: port, path: "/data/pkg/") ?? ""
        if !list.contains("PS4-Linux-v") {
            errors.append("/data/pkg/ has no PS4-Linux-v*.pkg")
        }

        for logPath in TitleConstants.bootLogPaths {
            if ftpFileExists(host: host, port: port, path: logPath) {
                print("  E2E: found log at \(logPath)")
            }
        }

        let appLog = "/user/app/CSTP00002/ps4-linux-app.log"
        if ftpFileExists(host: host, port: port, path: appLog) {
            if let body = ftpDownload(host: host, port: port, path: appLog), body.contains("eboot:") || body.contains("PS4 Linux") {
                print("  E2E: boot log content looks valid (\(body.count) bytes)")
            }
        } else {
            print("  E2E: no app log yet (launch PS4 Linux once after install)")
        }

        for e in errors {
            fputs("  FAIL: \(e)\n", stderr)
        }
        return errors.isEmpty ? 0 : 1
    }

    static func ftpReachable(host: String, port: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--connect-timeout", "3", "-m", "5", "ftp://\(host):\(port)/"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func ftpList(host: String, port: String, path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--connect-timeout", "5", "-m", "15", "ftp://\(host):\(port)\(path)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    static func ftpFileExists(host: String, port: String, path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--connect-timeout", "5", "-m", "20", "-f", "ftp://\(host):\(port)\(path)", "-o", "/dev/null"]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func ftpDownload(host: String, port: String, path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "--connect-timeout", "5", "-m", "30", "ftp://\(host):\(port)\(path)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
