// Sync PS4 internal Linux boot files over GoldHEN FTP — downloads, patches initramfs for auto install, uploads.
// Usage: swift tools/ps4-linux-sync.swift sync [--host 10.0.1.7] [--install-gb 100]
import CryptoKit
import Foundation

struct Config {
    var host = ProcessInfo.processInfo.environment["PS4_HOST"] ?? "10.0.1.7"
    var port = 2121
    var installGB = 100
    /// Bake initramfs stamp + upload HDD enable file for HTTP install log during kexec (port 8765).
    var installNetDebug: Bool = ProcessInfo.processInfo.environment["PS4LINUX_INSTALL_NETDEBUG"] == "1"
    let assetRoot: URL

    init() {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        assetRoot = repo.appendingPathComponent("downloads/ps4-linux-baikal", isDirectory: true)
    }

    static let psxitarchURL =
        "https://github.com/hippie68/psxitarch-how-to/releases/download/2021-08-19/psxitarch.tar.xz"
    /// hippie68 2021-08-19 release (~1.7 GB).
    static let psxitarchSHA256 = "2a48efae95b18eef1350bdda838ab6000d857055b2981ea893ef06b3d22394b4"
    static let psxitarchMinBytes: Int64 = 1_500_000_000
    static let nazkyInitramfsURL = "https://mega.nz/file/E0wW3a6Y#IE9fvrjZ22Q2mJ6kM1uQaNctwj1-we4cV7xGqPBVV64"
    static let bzImageURL =
        "https://github.com/feeRnt/ps4-linux-12xx/releases/download/v5.4.247__neocine-1.1/bzImage_GCC-11"
    /// feeRnt neocine Baikal kernel (Gladius / PS4 Pro lineage).
    static let bzImageExpectedBytes: Int64 = 9_872_896
    static let loaderZipURL =
        "https://github.com/ps4-linux/ps4-linux-loader/releases/download/v25.2/PS4-Linux-Loader-v25.2.zip"
}

enum SyncError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let s): return s
        }
    }
}

@discardableResult
func run(_ launchPath: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval = 7200) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = args
    if let cwd { task.currentDirectoryURL = cwd }
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    task.environment = env
    let out = Pipe()
    let err = Pipe()
    task.standardOutput = out
    task.standardError = err
    try task.run()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        task.waitUntilExit()
        group.leave()
    }
    if group.wait(timeout: .now() + timeout) == .timedOut {
        task.terminate()
        throw SyncError.message("\(launchPath) timed out")
    }
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard task.terminationStatus == 0 else {
        throw SyncError.message("\(launchPath) \(args.prefix(3).joined(separator: " ")) failed (\(task.terminationStatus)): \(stderr.prefix(800))")
    }
    return stdout + stderr
}

func sha256File(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
}

func downloadIfNeeded(url: String, to dest: URL, expectedSHA256: String?, minBytes: Int64? = nil) throws {
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let expectedSHA256, FileManager.default.fileExists(atPath: dest.path) {
        let got = try sha256File(dest)
        if got.lowercased() == expectedSHA256.lowercased() {
            print("OK (cached) \(dest.lastPathComponent)")
            return
        }
        if let minBytes, fileSize(dest) >= minBytes {
            print("Warning: \(dest.lastPathComponent) sha256 \(got) != catalog; keeping file (size OK)")
            return
        }
        print("Re-downloading \(dest.lastPathComponent) (sha256 mismatch)")
    } else if FileManager.default.fileExists(atPath: dest.path), expectedSHA256 == nil {
        print("OK (exists) \(dest.lastPathComponent)")
        return
    }
    print("Downloading \(dest.lastPathComponent)…")
    try run("/usr/bin/curl", ["-fL", "--retry", "3", "-o", dest.path, url], timeout: 7200)
    if let expectedSHA256 {
        let got = try sha256File(dest)
        guard got.lowercased() == expectedSHA256.lowercased() else {
            throw SyncError.message("\(dest.lastPathComponent) sha256 \(got) != \(expectedSHA256)")
        }
    }
    print("Downloaded \(dest.lastPathComponent)")
}

func buildAutoInitramfs(cfg: Config) throws -> URL {
    let base = cfg.assetRoot.appendingPathComponent("initramfs.nazky.cpio.gz")
    guard FileManager.default.fileExists(atPath: base.path) else {
        throw SyncError.message("Missing \(base.path) — run sync after Nazky initramfs is present")
    }
    let work = cfg.assetRoot.appendingPathComponent("initramfs-work", isDirectory: true)
    let out = cfg.assetRoot.appendingPathComponent("initramfs.cpio.gz")
    if FileManager.default.fileExists(atPath: work.path) {
        try FileManager.default.removeItem(at: work)
    }
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    _ = try run(
        "/bin/sh",
        ["-c", "gunzip -c '\(base.path)' | cpio -idmv 2>/dev/null"],
        cwd: work,
        timeout: 600
    )

    let overlayBin = cfg.assetRoot.appendingPathComponent("overlays/bin/install-HDD.sh")
    let overlaySnippet = cfg.assetRoot.appendingPathComponent("overlays/init-auto-install.snippet")
    try FileManager.default.createDirectory(at: work.appendingPathComponent("bin"), withIntermediateDirectories: true)
    let installDest = work.appendingPathComponent("bin/install-HDD.sh")
    if FileManager.default.fileExists(atPath: installDest.path) {
        try FileManager.default.removeItem(at: installDest)
    }
    try FileManager.default.copyItem(at: overlayBin, to: installDest)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installDest.path)

    let etcDir = work.appendingPathComponent("etc", isDirectory: true)
    try FileManager.default.createDirectory(at: etcDir, withIntermediateDirectories: true)
    let revStamp = etcDir.appendingPathComponent("ps4-linux-install-hdd.rev")
    try "4\n".write(to: revStamp, atomically: true, encoding: .utf8)

    let uiOverlay = cfg.assetRoot.appendingPathComponent("overlays/bin/ps4-linux-ui.sh")
    let uiDest = work.appendingPathComponent("bin/ps4-linux-ui.sh")
    if FileManager.default.fileExists(atPath: uiDest.path) {
        try FileManager.default.removeItem(at: uiDest)
    }
    try FileManager.default.copyItem(at: uiOverlay, to: uiDest)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uiDest.path)

    let netDebugOverlay = cfg.assetRoot.appendingPathComponent("overlays/bin/ps4-linux-install-netdebug.sh")
    let netDebugDest = work.appendingPathComponent("bin/ps4-linux-install-netdebug.sh")
    if FileManager.default.fileExists(atPath: netDebugOverlay.path) {
        if FileManager.default.fileExists(atPath: netDebugDest.path) {
            try FileManager.default.removeItem(at: netDebugDest)
        }
        try FileManager.default.copyItem(at: netDebugOverlay, to: netDebugDest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: netDebugDest.path)
    }
    let netDebugStamp = etcDir.appendingPathComponent("ps4-linux-install-netdebug")
    if cfg.installNetDebug {
        try "1\n".write(to: netDebugStamp, atomically: true, encoding: .utf8)
        let ndRev = etcDir.appendingPathComponent("ps4-linux-install-netdebug.rev")
        try "1\n".write(to: ndRev, atomically: true, encoding: .utf8)
        print("Initramfs: install netdebug enabled (HTTP :8765)")
    } else if FileManager.default.fileExists(atPath: netDebugStamp.path) {
        try FileManager.default.removeItem(at: netDebugStamp)
    }

    var initText = try String(contentsOf: work.appendingPathComponent("init"), encoding: .utf8)
    initText = initText.replacingOccurrences(
        of: "echo 0 > /proc/sys/kernel/printk",
        with: "echo 8 > /proc/sys/kernel/printk"
    )
    if initText.contains("cursor-setup: keep console visible") {
        print("init printk patch already applied")
    } else {
        initText = initText.replacingOccurrences(
            of: "# Clear the screen\nclear",
            with: "# cursor-setup: keep console visible\n# Clear the screen\nclear"
        )
    }
    let snippet = try String(contentsOf: overlaySnippet, encoding: .utf8)
    let marker = "mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd /ps4hdd\n"
    if initText.contains("cursor-setup: no Arch.img") {
        print("init already patched")
    } else if let range = initText.range(of: marker) {
        initText.replaceSubrange(range.upperBound..., with: "\n" + snippet + initText[range.upperBound...])
        try initText.write(to: work.appendingPathComponent("init"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.appendingPathComponent("init").path)
        print("Patched init for auto install-HDD")
    } else {
        throw SyncError.message("Could not patch init — Nazky layout changed")
    }

    if FileManager.default.fileExists(atPath: out.path) {
        try FileManager.default.removeItem(at: out)
    }
    _ = try run("/bin/sh", ["-c", "find . -print0 | cpio -o --null -H newc 2>/dev/null | gzip -9 > '\(out.path)'"], cwd: work, timeout: 600)
    print("Built \(out.path) (\(try FileManager.default.attributesOfItem(atPath: out.path)[.size] ?? 0) bytes)")
    try runInstallHddGuard(repoRoot: cfg.assetRoot.deletingLastPathComponent().deletingLastPathComponent())
    return out
}

func runInstallHddGuard(repoRoot: URL) throws {
    let tools = repoRoot.appendingPathComponent("tools/PS4LinuxTools", isDirectory: true)
    print("InstallHddScriptGuard (overlay + initramfs + arch/bzImage)…")
    fflush(stdout)
    _ = try run(
        "/usr/bin/swift",
        ["run", "--package-path", tools.path, "ps4-linux-install-guard", repoRoot.path],
        timeout: 300
    )
}

func waitForFTP(host: String, port: Int, attempts: Int = 60) throws {
    for i in 1 ... attempts {
        do {
            _ = try run("/usr/bin/curl", ["--connect-timeout", "5", "-m", "8", "-s", "ftp://\(host):\(port)/"])
            print("FTP ready at \(host):\(port)")
            return
        } catch {
            if i == attempts { throw SyncError.message("FTP not reachable at \(host):\(port) — boot PS4 to GoldHEN first") }
            print("Waiting for FTP (\(i)/\(attempts))…")
            Thread.sleep(forTimeInterval: 5)
        }
    }
}

func ftpUpload(local: URL, remotePath: String, host: String, port: Int) throws {
    let url = "ftp://\(host):\(port)\(remotePath)"
    let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
    print("\n>>> Upload \(local.lastPathComponent) (\(size) bytes) → \(remotePath)")
    fflush(stdout)
    _ = try runLive(
        "/usr/bin/curl",
        ["--ftp-create-dirs", "--connect-timeout", "15", "-m", "7200", "--progress-bar", "-T", local.path, url],
        timeout: 7200
    )
    print(">>> Done: \(local.lastPathComponent)\n")
    fflush(stdout)
}

@discardableResult
func runLive(_ launchPath: String, _ args: [String], timeout: TimeInterval = 7200) throws -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    task.environment = env
    task.standardOutput = FileHandle.standardError
    task.standardError = FileHandle.standardError
    try task.run()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        task.waitUntilExit()
        group.leave()
    }
    if group.wait(timeout: .now() + timeout) == .timedOut {
        task.terminate()
        throw SyncError.message("\(launchPath) timed out")
    }
    guard task.terminationStatus == 0 else {
        throw SyncError.message("\(launchPath) failed (\(task.terminationStatus))")
    }
    return task.terminationStatus
}

func ftpDelete(path: String, host: String, port: Int) {
    do {
        _ = try run("/usr/bin/curl", ["--connect-timeout", "10", "-m", "30", "-Q", "DELE \(path)", "ftp://\(host):\(port)/"])
        print("Deleted \(path)")
    } catch {
        print("Note: could not delete \(path) (may be absent)")
    }
}

func prepareAssets(cfg: Config) throws -> (initramfs: URL, arch: URL, installGBFile: URL) {
    try FileManager.default.createDirectory(at: cfg.assetRoot, withIntermediateDirectories: true)

    let bz = cfg.assetRoot.appendingPathComponent("bzImage")
    try downloadIfNeeded(url: Config.bzImageURL, to: bz, expectedSHA256: nil)
    let bzBytes = fileSize(bz)
    guard bzBytes == Config.bzImageExpectedBytes else {
        throw SyncError.message(
            "bzImage size \(bzBytes) != expected \(Config.bzImageExpectedBytes) — re-download feeRnt neocine kernel"
        )
    }
    print("OK bzImage \(bzBytes) bytes (feeRnt 5.4.247-neocine)")
    let nazky = cfg.assetRoot.appendingPathComponent("initramfs.nazky.cpio.gz")
    if !FileManager.default.fileExists(atPath: nazky.path) {
        if FileManager.default.fileExists(atPath: cfg.assetRoot.appendingPathComponent("initramfs.cpio.gz").path) {
            try FileManager.default.copyItem(
                at: cfg.assetRoot.appendingPathComponent("initramfs.cpio.gz"),
                to: nazky
            )
        } else {
            throw SyncError.message("Missing initramfs.nazky.cpio.gz under downloads/ps4-linux-baikal/")
        }
    }

    let arch = cfg.assetRoot.appendingPathComponent("psxitarch.tar.xz")
    try downloadIfNeeded(
        url: Config.psxitarchURL,
        to: arch,
        expectedSHA256: Config.psxitarchSHA256,
        minBytes: Config.psxitarchMinBytes
    )

    let initramfs = try buildAutoInitramfs(cfg: cfg)
    try ensureLoaderPayloads(cfg: cfg)

    let vram = cfg.assetRoot.appendingPathComponent("vram.txt")
    try "\(1024)\n".write(to: vram, atomically: true, encoding: .utf8)
    let bootargs = cfg.assetRoot.appendingPathComponent("bootargs.txt")
    try "panic=0 console=tty0 consoleblank=0 net.ifnames=0 rdinit=/init enforcing=0 video=HDMI-A-1:1920x1080@60 fbcon=nodefer loglevel=7 ignore_loglevel earlyprintk\n"
        .write(to: bootargs, atomically: true, encoding: .utf8)
    let installGBFile = cfg.assetRoot.appendingPathComponent("ps4-install-gb.txt")
    try "\(cfg.installGB)\n".write(to: installGBFile, atomically: true, encoding: .utf8)

    print("Prepared local assets under \(cfg.assetRoot.path)")
    return (initramfs, arch, installGBFile)
}

func uploadAssets(cfg: Config, initramfs: URL, arch: URL, installGBFile: URL) throws {
    let repoRoot = cfg.assetRoot.deletingLastPathComponent().deletingLastPathComponent()
    try runInstallHddGuard(repoRoot: repoRoot)

    try waitForFTP(host: cfg.host, port: cfg.port)

    ftpDelete(path: "/user/home/Arch.img", host: cfg.host, port: cfg.port)
    ftpDelete(path: "/user/system/boot/install-status.txt", host: cfg.host, port: cfg.port)
    ftpDelete(path: "/user/system/boot/ps4-linux-installed.meta", host: cfg.host, port: cfg.port)

    try ftpUpload(
        local: cfg.assetRoot.appendingPathComponent("bzImage"),
        remotePath: "/data/linux/boot/bzImage",
        host: cfg.host,
        port: cfg.port
    )
    try ftpUpload(local: initramfs, remotePath: "/data/linux/boot/initramfs.cpio.gz", host: cfg.host, port: cfg.port)
    try ftpUpload(
        local: cfg.assetRoot.appendingPathComponent("vram.txt"),
        remotePath: "/data/linux/boot/vram.txt",
        host: cfg.host,
        port: cfg.port
    )
    try ftpUpload(
        local: cfg.assetRoot.appendingPathComponent("bootargs.txt"),
        remotePath: "/data/linux/boot/bootargs.txt",
        host: cfg.host,
        port: cfg.port
    )
    try ftpUpload(local: arch, remotePath: "/user/system/boot/arch.tar.xz", host: cfg.host, port: cfg.port)
    try ftpUpload(local: installGBFile, remotePath: "/user/system/boot/ps4-install-gb.txt", host: cfg.host, port: cfg.port)

    if cfg.installNetDebug {
        let enable = cfg.assetRoot.appendingPathComponent("overlays/system/boot/ps4-install-netdebug.enable")
        try "enabled by ps4-linux-sync --netdebug\n".write(to: enable, atomically: true, encoding: .utf8)
        try ftpUpload(local: enable, remotePath: "/user/system/boot/ps4-install-netdebug.enable", host: cfg.host, port: cfg.port)
        let conf = cfg.assetRoot.appendingPathComponent("overlays/system/boot/ps4-install-netdebug.conf")
        if FileManager.default.fileExists(atPath: conf.path) {
            try ftpUpload(local: conf, remotePath: "/user/system/boot/ps4-install-netdebug.conf", host: cfg.host, port: cfg.port)
        }
        print("Tip: PS4 app writes ps4-net-inherit.conf before kexec (Wi‑Fi/LAN from Orbis)")
    }

    try uploadPayloads(cfg: cfg)

    let loaderPkgDir = cfg.assetRoot.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ps4-linux-launcher-app/linux-loader", isDirectory: true)
    if let entries = try? FileManager.default.contentsOfDirectory(at: loaderPkgDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
        let versioned = entries
            .filter { $0.pathExtension == "pkg" && $0.lastPathComponent.hasPrefix("PS4-Linux-v") }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        if let pkg = versioned.first {
            let remote = "/data/pkg/\(pkg.lastPathComponent)"
            print(">>> Upload PKG \(pkg.lastPathComponent) → \(remote)")
            try ftpUpload(local: pkg, remotePath: remote, host: cfg.host, port: cfg.port)
        } else if let legacy = entries.first(where: { $0.lastPathComponent.hasPrefix("IV0000-CSTP") }) {
            try ftpUpload(local: legacy, remotePath: "/data/pkg/\(legacy.lastPathComponent)", host: cfg.host, port: cfg.port)
        }
    }
}

func isElfFile(_ url: URL) -> Bool {
    guard let h = try? Data(contentsOf: url, options: [.mappedIfSafe, .alwaysMapped]), h.count >= 4 else {
        return false
    }
    return h[0] == 0x7f && h[1] == 0x45 && h[2] == 0x4c && h[3] == 0x46
}

func isKexecLoaderBin(_ url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    if isElfFile(url) { return false }
    let sz = fileSize(url)
    return sz >= 8192 && sz <= 2 * 1024 * 1024
}

func ensureLoaderPayloads(cfg: Config) throws {
    let zip = cfg.assetRoot.appendingPathComponent("PS4-Linux-Loader-v25.2.zip")
    if !FileManager.default.fileExists(atPath: zip.path) {
        try downloadIfNeeded(url: Config.loaderZipURL, to: zip, expectedSHA256: nil)
    }
    let bin = cfg.assetRoot.appendingPathComponent("linux-1024mb.bin")
    let elf = cfg.assetRoot.appendingPathComponent("linux-1024mb.elf")
    if !isKexecLoaderBin(bin) || !FileManager.default.fileExists(atPath: elf.path) {
        print("Extracting ps4-linux-loader v25.2 kexec .bin + .elf…")
        _ = try run("/usr/bin/unzip", ["-o", "-j", zip.path, "bin/linux-1024mb.bin", "-d", cfg.assetRoot.path])
        _ = try run("/usr/bin/unzip", ["-o", "-j", zip.path, "elf/linux-1024mb.elf", "-d", cfg.assetRoot.path])
    }
    guard isKexecLoaderBin(bin) else {
        throw SyncError.message("\(bin.path) is not a kexec loader (expected ~329088 B, not ELF)")
    }

    let payloadDir = cfg.assetRoot.appendingPathComponent("payloads", isDirectory: true)
    try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
    for name in ["linux-1gb-pro-baikal.bin", "payload-1100-1gb-pro-baikal.bin"] {
        let alias = payloadDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: alias.path) {
            try FileManager.default.removeItem(at: alias)
        }
        try FileManager.default.copyItem(at: bin, to: alias)
    }
    let meta = payloadDir.appendingPathComponent("meta.json")
    try """
    {"source":"ps4-linux-loader-v25.2","kexec_bin_bytes":\(fileSize(bin)),"note":"Baikal aliases are copies of linux-1024mb.bin until dedicated pro-baikal kexec exists"}
    """.write(to: meta, atomically: true, encoding: .utf8)
}

func uploadPayloads(cfg: Config) throws {
    try ensureLoaderPayloads(cfg: cfg)
    try waitForFTP(host: cfg.host, port: cfg.port)

    let bin = cfg.assetRoot.appendingPathComponent("linux-1024mb.bin")
    let elf = cfg.assetRoot.appendingPathComponent("linux-1024mb.elf")
    let payloadDir = cfg.assetRoot.appendingPathComponent("payloads", isDirectory: true)

    let uploads: [(URL, String)] = [
        (bin, "/data/payloads/linux-1024mb.bin"),
        (elf, "/data/payloads/linux-1024mb.elf"),
        (payloadDir.appendingPathComponent("linux-1gb-pro-baikal.bin"), "/data/payloads/linux-1gb-pro-baikal.bin"),
        (payloadDir.appendingPathComponent("payload-1100-1gb-pro-baikal.bin"), "/data/payloads/payload-1100-1gb-pro-baikal.bin"),
        (payloadDir.appendingPathComponent("meta.json"), "/data/payloads/meta.json"),
    ]
    for (local, remote) in uploads {
        try ftpUpload(local: local, remotePath: remote, host: cfg.host, port: cfg.port)
    }
    print("\n=== Payloads OK ===\nReal kexec .bin (~329 KiB, magic e9…) replaces ELF misnamed .bin files on console.\n")
}

func sync(cfg: Config) throws {
    print("\n========== PS4 Linux sync started (host \(cfg.host)) ==========\n")
    fflush(stdout)
    let bundle = try prepareAssets(cfg: cfg)
    print("\n========== FTP upload phase ==========\n")
    fflush(stdout)
    try uploadAssets(cfg: cfg, initramfs: bundle.initramfs, arch: bundle.arch, installGBFile: bundle.installGBFile)

    print(
        """

        === Done ===
        On PS4 (no Mac, no USB after this):
          1. Unplug USB storage.
          2. Library → Payload Guest → **PS4 Linux** (uses linux-1024mb.bin + /data/linux/boot/).
        Or: GoldHEN → PayLoader → linux-1024mb.elf
        First boot auto-runs install-HDD.sh (\(cfg.installGB) GB) if Arch.img missing — 30–90+ min.
        Install Payload Guest once: docs/PS4-LINUX-XMB-LAUNCH.md
        """
    )
}

func parseArgs(_ args: [String]) -> (command: String, cfg: Config) {
    var cfg = Config()
    var command = "sync"
    var i = 0
    if i < args.count, !args[i].hasPrefix("-") {
        command = args[i]
        i += 1
    }
    while i < args.count {
        switch args[i] {
        case "--host":
            i += 1
            if i < args.count { cfg.host = args[i] }
        case "--install-gb":
            i += 1
            if i < args.count, let n = Int(args[i]) { cfg.installGB = max(50, n) }
        case "--netdebug":
            cfg.installNetDebug = true
        default:
            break
        }
        i += 1
    }
    return (command, cfg)
}

let args = Array(CommandLine.arguments.dropFirst())
let (command, cfg) = parseArgs(args)

do {
    switch command {
    case "sync":
        try sync(cfg: cfg)
    case "prepare":
        _ = try prepareAssets(cfg: cfg)
    case "upload":
        let bundle = try prepareAssets(cfg: cfg)
        try uploadAssets(cfg: cfg, initramfs: bundle.initramfs, arch: bundle.arch, installGBFile: bundle.installGBFile)
        print("\n=== Upload done ===\nPayLoader → linux-1024mb.elf (no USB, no rescue typing).\n")
    case "payloads":
        try uploadPayloads(cfg: cfg)
    default:
        print(
            """
            Usage:
              swift tools/ps4-linux-sync.swift sync [--host 10.0.1.7] [--install-gb 100] [--netdebug]
              swift tools/ps4-linux-sync.swift prepare [--install-gb 100] [--netdebug]
              swift tools/ps4-linux-sync.swift upload [--host 10.0.1.7] [--install-gb 100] [--netdebug]
              swift tools/ps4-linux-sync.swift payloads [--host 10.0.1.7]
            Env: PS4LINUX_INSTALL_NETDEBUG=1 same as --netdebug
            """
        )
        exit(1)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
