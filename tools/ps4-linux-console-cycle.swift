#!/usr/bin/env swift
// Automate PS4 Linux deploy: discover FTP, upload PKG + guest fallback, trigger GoldHEN install API, poll logs.
// Usage:
//   swift tools/ps4-linux-console-cycle.swift upload [--host 10.0.1.7]
//   swift tools/ps4-linux-console-cycle.swift cycle [--host 10.0.1.7] [--wait-seconds 120]
//   swift tools/ps4-linux-console-cycle.swift logs [--host 10.0.1.7]
//   swift tools/ps4-linux-console-cycle.swift status [--host 10.0.1.7]
import Foundation

struct Config {
    var host = ProcessInfo.processInfo.environment["PS4_HOST"] ?? "10.0.1.7"
    var port = 2121
    var waitSeconds = 120
    var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}

@discardableResult
func runCurl(_ args: [String], timeout: Int = 120) throws -> (stdout: String, status: Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    task.arguments = ["--connect-timeout", "15", "-m", "\(timeout)", "-sS"] + args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/bin:/bin"
    task.environment = env
    let out = Pipe()
    let err = Pipe()
    task.standardOutput = out
    task.standardError = err
    try task.run()
    task.waitUntilExit()
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (stdout + stderr, task.terminationStatus)
}

func discoverHost(preferred: String) -> String? {
    if (try? runCurl(["ftp://\(preferred):2121/"], timeout: 5)).map({ $0.status == 0 }) == true {
        return preferred
    }
    let local = (try? runShell("/sbin/ipconfig", ["getifaddr", "en0"])) ??
        (try? runShell("/sbin/ipconfig", ["getifaddr", "en1"])) ?? ""
    let parts = local.split(separator: ".")
    guard parts.count == 4 else { return nil }
    let base = parts.prefix(3).joined(separator: ".")
    for i in 1 ... 254 {
        let h = "\(base).\(i)"
        if h == local { continue }
        if (try? runCurl(["ftp://\(h):2121/"], timeout: 1)).map({ $0.status == 0 }) == true {
            return h
        }
    }
    return nil
}

func runShell(_ path: String, _ args: [String]) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    let out = Pipe()
    task.standardOutput = out
    try task.run()
    task.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func latestPkg(in loader: URL) -> URL? {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: loader, includingPropertiesForKeys: [.contentModificationDateKey]) else {
        return nil
    }
    return items
        .filter { $0.lastPathComponent.hasPrefix("PS4-Linux-v") && $0.pathExtension == "pkg" }
        .sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        .first
}

func ftpUpload(host: String, port: Int, local: URL, remotePath: String) throws {
    let url = "ftp://\(host):\(port)\(remotePath)"
    let (out, status) = try runCurl(["--ftp-create-dirs", "-T", local.path, url], timeout: 7200)
    guard status == 0 else { throw NSError(domain: "console-cycle", code: Int(status), userInfo: [NSLocalizedDescriptionKey: out]) }
}

func ftpDelete(host: String, port: Int, remotePath: String) {
    guard let (_, st) = try? runCurl(["-Q", "DELE \(remotePath)", "ftp://\(host):\(port)/"], timeout: 30), st == 0 else {
        return
    }
    print("Deleted stale \(remotePath)")
}

func ftpListNames(host: String, port: Int, remoteDir: String) -> [String] {
    guard let (body, st) = try? runCurl(["ftp://\(host):\(port)\(remoteDir)"], timeout: 30), st == 0 else {
        return []
    }
    return body.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let name = parts.last, name.hasSuffix(".pkg") else { return nil }
        return String(name)
    }
}

/// Remove every PS4-Linux PKG in /data/pkg/ except the one we are about to install.
func cleanupStalePs4LinuxPkgs(host: String, port: Int, keepFileName: String) {
    for name in ftpListNames(host: host, port: port, remoteDir: "/data/pkg/") {
        guard name.hasPrefix("PS4-Linux-v"), name != keepFileName else { continue }
        ftpDelete(host: host, port: port, remotePath: "/data/pkg/\(name)")
    }
}

func cleanupStaleMenuCaches(host: String, port: Int) {
    let stale = [
        "/data/self/guest.elf",
        "/data/linux/boot/ps4linux_menu.fself",
        "/data/linux/boot/ps4linux_guest.elf",
        "/user/data/guest.elf",
        "/user/data/ps4linux_menu.fself",
    ]
    for path in stale {
        ftpDelete(host: host, port: port, remotePath: path)
    }
}

func remoteInstallPkg(host: String, pkgFileName: String) {
    // Do NOT POST JSON to :9090 — GoldHEN BinLoader treats it as a payload → "invalid payload format".
    print("Skip HTTP :9090/api/install (BinLoader is not PKG installer; use Package Installer on console).")
    print("On PS4: Package Installer → /data/pkg/\(pkgFileName)")
    print("FTP:    ftp://\(host):2121/data/pkg/\(pkgFileName)")
}

func uploadPkg(host: String, port: Int, pkg: URL) throws {
    cleanupStaleMenuCaches(host: host, port: port)
    cleanupStalePs4LinuxPkgs(host: host, port: port, keepFileName: pkg.lastPathComponent)

    print("Upload PKG \(pkg.lastPathComponent) → /data/pkg/ …")
    try ftpUpload(host: host, port: port, local: pkg, remotePath: "/data/pkg/\(pkg.lastPathComponent)")

    let loader = pkg.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: loader.appendingPathComponent("assets/boot/guest.oelf").path) {
        print("Upload plain menu → /data/linux/boot/guest.oelf …")
        try ftpUpload(host: host, port: port, local: loader.appendingPathComponent("assets/boot/guest.oelf"), remotePath: "/data/linux/boot/guest.oelf")
    }

    remoteInstallPkg(host: host, pkgFileName: pkg.lastPathComponent)
    resetBootLogsForFreshRun(host: host, port: port, pkgFileName: pkg.lastPathComponent)
}

func resetBootLogsForFreshRun(host: String, port: Int, pkgFileName: String) {
    let logs = [
        "/data/linux/boot/ps4-linux-app.log",
        "/data/linux/boot/ps4-linux-last-run.txt",
        "/data/pkg/ps4-linux-app.log",
    ]
    for path in logs {
        ftpDelete(host: host, port: port, remotePath: path)
    }
    let marker = "After install, open PS4 Linux once. Expect RUN START + step: lines from \(pkgFileName)\n"
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ps4-linux-install-marker.txt")
    try? marker.write(to: tmp, atomically: true, encoding: .utf8)
    if let (_, st) = try? runCurl([
        "--ftp-create-dirs", "-T", tmp.path,
        "ftp://\(host):\(port)/data/linux/boot/INSTALL-MARKER.txt",
    ], timeout: 60), st == 0 {
        print("Wrote /data/linux/boot/INSTALL-MARKER.txt (old log cleared for next launch)")
    }
}

func pullLog(host: String, port: Int, path: String) -> String? {
    guard let (body, st) = try? runCurl(["ftp://\(host):\(port)\(path)"], timeout: 30), st == 0 else { return nil }
    return body
}

func installedPkgName(host: String, port: Int) -> String? {
    guard let json = pullLog(host: host, port: port, path: "/user/app/CSTP00003/app.json"),
          let range = json.range(of: "PS4-Linux-v") else { return nil }
    let tail = json[range.lowerBound...]
    if let end = tail.firstIndex(of: "\"") {
        return String(tail[..<end])
    }
    return nil
}

func printStatus(host: String, port: Int, repoRoot: URL) {
    let loader = repoRoot.appendingPathComponent("ps4-linux-launcher-app/linux-loader")
    let macPkg = latestPkg(in: loader)?.lastPathComponent ?? "(none built on Mac)"
    let installed = installedPkgName(host: host, port: port) ?? "(CSTP00003 not installed)"
    let log = (pullLog(host: host, port: port, path: "/data/linux/boot/ps4-linux-last-run.txt") ?? "")
        + (pullLog(host: host, port: port, path: "/data/linux/boot/ps4-linux-app.log") ?? "")
        + (pullLog(host: host, port: port, path: "/data/pkg/ps4-linux-app.log") ?? "")
        + (pullLog(host: host, port: port, path: "/user/app/CSTP00003/ps4-linux-app.log") ?? "")

    print("=== PS4 Linux status ===")
    print("Mac latest PKG:     \(macPkg)")
    print("Console installed:  \(installed)")

    if installed == "(CSTP00003 not installed)" {
        print("\nNext: Package Installer → /data/pkg/\(macPkg) (delete old tile first if reinstall fails)")
        print("      GoldHEN: disable Background Installation. See tmp/docs/PS4-LINUX-INTERNAL-RUNBOOK.md §4.")
        return
    }

    if !installed.contains("PS4-Linux-v") {
        print("\nNext: Install PS4-Linux-v*.pkg for CSTP00003")
        return
    }

    if log.isEmpty {
        print("\nState: No boot log lines (CE-41839-5 if Library shows blue error — kernel rejects SELF before BootTrace runs).")
        print("Next:  Install latest PKG (HeaderSize/MetaSize 0x440/0x470 for unified eboot). Launch once, then logs.")
        print("        swift tools/ps4-linux-console-cycle.swift logs")
        return
    }

    if log.contains("loader: running") || log.contains("guestPlainLoaderRun") || log.contains("plain ELF loader") {
        if installed.contains("0.7.60") || installed.contains("b129") {
            print("\nState: Log file has OLD split-chain runs (0.7.56–0.7.58). Installed app IS unified 0.7.60.")
            print("Next:  Open PS4 Linux once — new lines must show `unified OpenOrbis eboot`, not `loader: running`.")
        } else {
            print("\nState: Split-chain build ran (CE-34878). Install \(macPkg), delete tile first.")
        }
        return
    }
    if log.contains("41839") {
        print("\nState: Console reported CE-41839. Capture Package Installer moment; do NOT revert to split eboot.")
        print("Next:  Compare create-fself signing (see tmp/docs/PS4-LINUX-INTERNAL-RUNBOOK.md §3–§7).")
        return
    }
    if log.contains("30008") {
        print("\nState: CE-30008-1 (corrupt PKG or bad SELF patch). Delete tile, reinstall latest from /data/pkg/.")
        print("       If on 0.7.75: avoid npdrm_exec + @0x70 patch — use 0.7.76+ (fake ptype, no header patch, full sce_module).")
        return
    }
    if log.contains("app: guest main entered") {
        if log.contains("step: 22 first frame presented") {
            print("\nState: OK — unified eboot, UI presented (if HDMI black, check TV input / not CE-34878 split-chain).")
        } else if log.contains("step: 21 Application Run loop") {
            print("\nState: OK — main loop running; no step 22 yet (launch again or wait for first frame).")
            print("       CE-34878 on PS button exit is normal if logs show step 21 — not split-chain.")
        } else {
            print("\nState: OK — unified eboot reached main().")
        }
        return
    }
    if log.contains("unified OpenOrbis eboot") || log.contains("RUN START") {
        print("\nState: App started but died before main() — UI/module crash, not install layout.")
        print("Next:  Pull full logs; fix Graphics/pad/modules — not another eboot split.")
        return
    }
    print("\nState: Unknown log — paste output of `logs` command.")
}

func printLogs(host: String, port: Int) {
    let paths = [
        "/data/linux/boot/ps4-linux-last-run.txt",
        "/data/linux/boot/ps4-linux-app.log",
        "/data/pkg/ps4-linux-app.log",
        "/data/linux/boot/INSTALL-MARKER.txt",
        "/user/app/CSTP00003/ps4-linux-app.log",
        "/user/data/ps4-linux-app.log",
        "/user/data/ps4-linux-early.txt",
        "/data/pkg/ps4-linux-early.txt",
        "/user/system/boot/ps4-linux-app.log",
        "/data/pkg/ps4-linux-minimal.log",
        "/user/data/ps4-linux-minimal.log",
    ]
    for p in paths {
        print("\n========== \(p) ==========")
        if let body = pullLog(host: host, port: port, path: p), !body.isEmpty {
            print(body)
        } else {
            print("(missing or empty)")
        }
    }
}

func cycle(cfg: Config) throws {
    var host = cfg.host
    if (try? runCurl(["ftp://\(host):\(cfg.port)/"], timeout: 5)).map({ $0.status == 0 }) != true {
        print("FTP not up on \(host), scanning LAN…")
        guard let found = discoverHost(preferred: host) else {
            throw NSError(domain: "console-cycle", code: 1, userInfo: [NSLocalizedDescriptionKey: "No GoldHEN FTP on LAN (port 2121)"])
        }
        host = found
        print("Using PS4 at \(host)")
    }

    let loader = cfg.repoRoot.appendingPathComponent("ps4-linux-launcher-app/linux-loader")
    guard let pkg = latestPkg(in: loader) else {
        throw NSError(domain: "console-cycle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No PS4-Linux-v*.pkg — run ps4-linux-launcher-build.swift first"])
    }

    try uploadPkg(host: host, port: cfg.port, pkg: pkg)

    print("\nWaiting up to \(cfg.waitSeconds)s for new log lines (launch PS4 Linux on the console if it does not auto-open)…")
    let baseline = pullLog(host: host, port: cfg.port, path: "/data/linux/boot/ps4-linux-app.log") ?? ""
    let deadline = Date().addingTimeInterval(TimeInterval(cfg.waitSeconds))
    var last = baseline
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 8)
        let now = pullLog(host: host, port: cfg.port, path: "/data/linux/boot/ps4-linux-app.log") ?? ""
        if now != last {
            last = now
            if now.contains("app: guest main entered") || now.contains("step: 10") {
                print("\n*** Guest started — menu should be up ***\n")
                break
            }
            if now.contains("loader: running") || now.contains("guestPlainLoaderRun") {
                print("\n*** Split-chain loader detected — wrong/stale build ***\n")
                break
            }
            if now.contains("unified OpenOrbis eboot") && !now.contains("app: guest main entered") {
                print("\n*** Unified eboot ran but guest main missing — crash after start ***\n")
                break
            }
        }
    }

    printLogs(host: host, port: cfg.port)

    if last.contains("guest.elf ok size=3200") || last.contains("size=3200 magic=") {
        print("\nDiagnosis: broken ~3200 B menu on console — Delete PS4 Linux tile, install latest PKG from /data/pkg/, then open app once.")
    }
    if last.contains("LoadExec Mac-synced menu") && !last.contains("app: guest main entered") {
        print("\nDiagnosis: chain used /data/linux/boot/guest.elf — check LoadExec returned line; reinstall PKG if app0 assets missing.")
    }
    if last.contains("app: guest main entered") || last.contains("step: 10") {
        print("\nResult: SUCCESS — unified eboot reached main().")
    } else if last.contains("loader: running") {
        print("\nResult: FAIL — split-chain / CE-34878 path. Delete tile, install latest unified PKG.")
    } else if last.contains("unified OpenOrbis eboot") {
        print("\nResult: partial — unified start OK, crash before main (not fixed by split eboot).")
    } else if last.isEmpty {
        print("\nResult: no launch yet — open PS4 Linux from Library once.")
    } else if last.contains("eboot:") && !last.contains("app:") {
        print("\nResult: stale chain-only log — delete tile, reinstall unified PKG.")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
var cfg = Config()
var cmd = "cycle"
var i = 0
while i < args.count {
    switch args[i] {
    case "--host":
        i += 1
        if i < args.count { cfg.host = args[i] }
    case "--wait-seconds":
        i += 1
        if i < args.count, let n = Int(args[i]) { cfg.waitSeconds = max(15, n) }
    case "cycle", "logs", "upload", "status", "clean-pkg":
        cmd = args[i]
    default:
        break
    }
    i += 1
}

do {
    switch cmd {
    case "status":
        printStatus(host: cfg.host, port: cfg.port, repoRoot: cfg.repoRoot)
    case "logs":
        printLogs(host: cfg.host, port: cfg.port)
    case "clean-pkg":
        var hostClean = cfg.host
        if (try? runCurl(["ftp://\(hostClean):\(cfg.port)/"], timeout: 5)).map({ $0.status == 0 }) != true {
            guard let found = discoverHost(preferred: hostClean) else {
                throw NSError(domain: "console-cycle", code: 1, userInfo: [NSLocalizedDescriptionKey: "No GoldHEN FTP on LAN (port 2121)"])
            }
            hostClean = found
            print("Using PS4 at \(hostClean)")
        }
        let loaderClean = cfg.repoRoot.appendingPathComponent("ps4-linux-launcher-app/linux-loader")
        let keep = latestPkg(in: loaderClean)?.lastPathComponent ?? ""
        for name in ftpListNames(host: hostClean, port: cfg.port, remoteDir: "/data/pkg/") {
            guard name.hasPrefix("PS4-Linux-v") else { continue }
            if !keep.isEmpty, name == keep { continue }
            ftpDelete(host: hostClean, port: cfg.port, remotePath: "/data/pkg/\(name)")
        }
        print("Remaining in /data/pkg/:")
        for name in ftpListNames(host: hostClean, port: cfg.port, remoteDir: "/data/pkg/") {
            print("  \(name)")
        }
    case "upload":
        var host = cfg.host
        if (try? runCurl(["ftp://\(host):\(cfg.port)/"], timeout: 5)).map({ $0.status == 0 }) != true {
            guard let found = discoverHost(preferred: host) else {
                throw NSError(domain: "console-cycle", code: 1, userInfo: [NSLocalizedDescriptionKey: "No GoldHEN FTP on LAN (port 2121)"])
            }
            host = found
            print("Using PS4 at \(host)")
        }
        let loader = cfg.repoRoot.appendingPathComponent("ps4-linux-launcher-app/linux-loader")
        guard let pkg = latestPkg(in: loader) else {
            throw NSError(domain: "console-cycle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No PS4-Linux-v*.pkg — run ps4-linux-launcher-build.swift first"])
        }
        try uploadPkg(host: host, port: cfg.port, pkg: pkg)
        print("\n/data/pkg/ now:")
        for name in ftpListNames(host: host, port: cfg.port, remoteDir: "/data/pkg/") {
            print("  \(name)")
        }
    default:
        try cycle(cfg: cfg)
    }
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
