#!/usr/bin/env swift
// Remote control PS4: GoldHEN FTP (PS4 OS) or SSH (Arch Linux).
// Usage:
//   swift tools/ps4-linux-remote.swift probe [--host 10.0.1.7]
//   swift tools/ps4-linux-remote.swift setup [--host 10.0.1.7]     # SSH key + bootstrap instructions
//   swift tools/ps4-linux-remote.swift serve [--port 8766]       # HTTP scripts + pubkey for curl|bash
//   swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- uname -a
//   swift tools/ps4-linux-remote.swift push --host 10.0.1.7 local.txt /tmp/remote.txt
//   swift tools/ps4-linux-remote.swift pull --host 10.0.1.7 /etc/hostname ./hostname
import Foundation

struct Cfg {
    var host = ProcessInfo.processInfo.environment["PS4_HOST"] ?? "10.0.1.7"
    var ftpPort = 2121
    var httpPort = 8766
    var sshUser = ProcessInfo.processInfo.environment["PS4_SSH_USER"] ?? "root"
    var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    var sshKey: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/ps4_linux_ed25519")
    }
    var scriptsDir: URL { repoRoot.appendingPathComponent("scripts/linux-postinstall", isDirectory: true) }
}

@discardableResult
func sh(_ launch: String, _ args: [String], timeout: Int = 120) throws -> (String, Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launch)
    task.arguments = args
    let out = Pipe()
    let err = Pipe()
    task.standardOutput = out
    task.standardError = err
    try task.run()
    task.waitUntilExit()
    let s = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        + (String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    return (s, task.terminationStatus)
}

func lanIP() -> String {
    let ipconfig = "/usr/sbin/ipconfig"
    for iface in ["en0", "en1", "bridge0"] {
        if let (raw, st) = try? sh(ipconfig, ["getifaddr", iface], timeout: 5), st == 0 {
            let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty { return ip }
        }
    }
    return "127.0.0.1"
}

func ensureSSHKey(_ cfg: Cfg) throws -> URL {
    let pub = cfg.sshKey.appendingPathExtension("pub")
    if FileManager.default.fileExists(atPath: cfg.sshKey.path) {
        return cfg.sshKey
    }
  let sshDir = cfg.sshKey.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)
    let (_, st) = try sh("/usr/bin/ssh-keygen", ["-t", "ed25519", "-f", cfg.sshKey.path, "-N", "", "-C", "ps4-linux-remote"])
    guard st == 0, FileManager.default.fileExists(atPath: pub.path) else {
        throw NSError(domain: "remote", code: 1, userInfo: [NSLocalizedDescriptionKey: "ssh-keygen failed"])
    }
    print("Created \(cfg.sshKey.path)")
    return cfg.sshKey
}

enum OsMode { case goldhenFTP, archSSH, offline }

func probe(_ host: String, ftpPort: Int, key: URL) -> OsMode {
    if FileManager.default.fileExists(atPath: key.path) {
        if let (_, st) = try? sh("/usr/bin/ssh", [
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=4", "-o", "StrictHostKeyChecking=no",
            "-i", key.path, "root@\(host)", "true",
        ], timeout: 8), st == 0 {
            return .archSSH
        }
    }
    if let (_, st) = try? sh("/usr/bin/curl", ["--connect-timeout", "3", "-m", "5", "ftp://\(host):\(ftpPort)/"], timeout: 8),
       st == 0
    {
        return .goldhenFTP
    }
    return .offline
}

func sshBase(_ cfg: Cfg) -> [String] {
    let a = [
        "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
        "-i", cfg.sshKey.path, "\(cfg.sshUser)@\(cfg.host)",
    ]
    if FileManager.default.fileExists(atPath: cfg.sshKey.path) {
        return ["-o", "BatchMode=yes"] + a
    }
    return a
}

func runSetup(_ cfg: Cfg) throws {
    _ = try ensureSSHKey(cfg)
    let pub = try String(contentsOf: cfg.sshKey.appendingPathExtension("pub"), encoding: .utf8)
    let staging = cfg.repoRoot.appendingPathComponent("tmp/ps4-linux-pubkey", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let pubFile = staging.appendingPathComponent("ps4-linux.pub")
    try pub.write(to: pubFile, atomically: true, encoding: .utf8)

    let mac = lanIP().trimmingCharacters(in: .whitespacesAndNewlines)
    print("""
    === PS4 Linux remote setup ===
    SSH key: \(cfg.sshKey.path)

    1) Leave this running in another terminal (serves scripts + pubkey):
         swift tools/ps4-linux-remote.swift serve

    2) On PS4 Linux (one-time, in Terminal):
         curl -fsSL "http://\(mac):\(cfg.httpPort)/enable-mac-control.sh" | sudo bash -s -- "http://\(mac):\(cfg.httpPort)/ps4-linux.pub"

    3) From Mac then:
         swift tools/ps4-linux-remote.swift exec --host \(cfg.host) -- uname -a
         swift tools/ps4-linux-remote.swift exec --host \(cfg.host) -- pacman -Syu

    On PS4 OS (GoldHEN), pubkey is also uploaded to /data/linux/boot/ps4-linux.pub when you run:
         swift tools/ps4-linux-remote.swift upload-bootstrap --host \(cfg.host)
    """)
    switch probe(cfg.host, ftpPort: cfg.ftpPort, key: cfg.sshKey) {
    case .goldhenFTP:
        print("\n(probe: GoldHEN FTP up — run upload-bootstrap now if Linux is not running)")
    case .archSSH:
        print("\n(probe: SSH already works — try exec)")
    case .offline:
        print("\n(probe: host not reachable on FTP or SSH)")
    }
}

func uploadBootstrap(_ cfg: Cfg) throws {
    _ = try ensureSSHKey(cfg)
    let pub = cfg.sshKey.appendingPathExtension("pub")
    let enable = cfg.scriptsDir.appendingPathComponent("enable-mac-control.sh")
    guard let (_, st) = try? sh("/usr/bin/curl", ["--connect-timeout", "5", "-m", "10", "ftp://\(cfg.host):\(cfg.ftpPort)/"], timeout: 15),
          st == 0
    else {
        throw NSError(domain: "remote", code: 2, userInfo: [NSLocalizedDescriptionKey: "GoldHEN FTP not up"])
    }
    let (out1, s1) = try sh("/usr/bin/curl", [
        "--ftp-create-dirs", "-T", pub.path,
        "ftp://\(cfg.host):\(cfg.ftpPort)/data/linux/boot/ps4-linux.pub",
    ], timeout: 120)
    let (out2, s2) = try sh("/usr/bin/curl", [
        "--ftp-create-dirs", "-T", enable.path,
        "ftp://\(cfg.host):\(cfg.ftpPort)/data/linux/boot/enable-mac-control.sh",
    ], timeout: 120)
    guard s1 == 0, s2 == 0 else {
        throw NSError(domain: "remote", code: 3, userInfo: [NSLocalizedDescriptionKey: out1 + out2])
    }
    print("Uploaded /data/linux/boot/ps4-linux.pub + enable-mac-control.sh")
}

func serveHTTP(_ cfg: Cfg, port: Int) throws {
    _ = try ensureSSHKey(cfg)
    let staging = cfg.repoRoot.appendingPathComponent("tmp/ps4-linux-pubkey", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let linkPub = staging.appendingPathComponent("ps4-linux.pub")
    if !FileManager.default.fileExists(atPath: linkPub.path) {
        try FileManager.default.copyItem(at: cfg.sshKey.appendingPathExtension("pub"), to: linkPub)
    }
    for name in ["enable-mac-control.sh", "ubuntu-look-arch.sh", "ubuntu-look-one-liner.sh"] {
        let src = cfg.scriptsDir.appendingPathComponent(name)
        let dst = staging.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: src.path) {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }
    let mac = lanIP()
    print("Serving \(staging.path) at http://\(mac):\(port)/")
    print("Bootstrap: curl -fsSL \"http://\(mac):\(port)/enable-mac-control.sh\" | sudo bash -s -- \"http://\(mac):\(port)/ps4-linux.pub\"")
    fflush(stdout)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    task.arguments = ["-m", "http.server", "\(port)", "--bind", "0.0.0.0", "--directory", staging.path]
    try task.run()
    task.waitUntilExit()
}

func execSSH(_ cfg: Cfg, command: [String]) throws {
    _ = try ensureSSHKey(cfg)
    guard !command.isEmpty else {
        throw NSError(domain: "remote", code: 4, userInfo: [NSLocalizedDescriptionKey: "missing command after --"])
    }
    let (out, st) = try sh("/usr/bin/ssh", sshBase(cfg) + command, timeout: 3600)
    print(out, terminator: "")
    guard st == 0 else {
        throw NSError(domain: "remote", code: Int(st), userInfo: [NSLocalizedDescriptionKey: "ssh exit \(st)"])
    }
}

func scpPush(_ cfg: Cfg, local: String, remote: String) throws {
    _ = try ensureSSHKey(cfg)
    let (_, st) = try sh("/usr/bin/scp", ["-o", "StrictHostKeyChecking=no", "-i", cfg.sshKey.path, local, "\(cfg.sshUser)@\(cfg.host):\(remote)"])
    guard st == 0 else { throw NSError(domain: "remote", code: 5, userInfo: [NSLocalizedDescriptionKey: "scp push failed"]) }
}

func scpPull(_ cfg: Cfg, remote: String, local: String) throws {
    _ = try ensureSSHKey(cfg)
    let (_, st) = try sh("/usr/bin/scp", ["-o", "StrictHostKeyChecking=no", "-i", cfg.sshKey.path, "\(cfg.sshUser)@\(cfg.host):\(remote)", local])
    guard st == 0 else { throw NSError(domain: "remote", code: 6, userInfo: [NSLocalizedDescriptionKey: "scp pull failed"]) }
}

var cfg = Cfg()
var cmd = "probe"
var execArgs: [String] = []
var i = 0
let argv = Array(CommandLine.arguments.dropFirst())
while i < argv.count {
    switch argv[i] {
    case "--host":
        i += 1
        if i < argv.count { cfg.host = argv[i] }
    case "--port":
        i += 1
        if i < argv.count, let p = Int(argv[i]) { cfg.httpPort = p }
    case "probe", "setup", "serve", "exec", "push", "pull", "upload-bootstrap":
        cmd = argv[i]
    case "--":
        execArgs = Array(argv[(i + 1)...])
        i = argv.count
    default:
        if ["exec", "push", "pull"].contains(cmd), !argv[i].hasPrefix("-") {
            execArgs.append(argv[i])
        }
        break
    }
    i += 1
}

do {
    switch cmd {
    case "probe":
        let m = probe(cfg.host, ftpPort: cfg.ftpPort, key: cfg.sshKey)
        switch m {
        case .goldhenFTP: print("\(cfg.host): GoldHEN FTP (PS4 OS)")
        case .archSSH: print("\(cfg.host): Arch SSH (Linux)")
        case .offline: print("\(cfg.host): offline (no FTP:2121 / SSH)")
        }
    case "setup":
        try runSetup(cfg)
    case "upload-bootstrap":
        try uploadBootstrap(cfg)
    case "serve":
        try serveHTTP(cfg, port: cfg.httpPort)
    case "exec":
        try execSSH(cfg, command: execArgs)
    case "push":
        guard execArgs.count >= 2 else { fatalError("push local remote") }
        try scpPush(cfg, local: execArgs[0], remote: execArgs[1])
    case "pull":
        guard execArgs.count >= 2 else { fatalError("pull remote local") }
        try scpPull(cfg, remote: execArgs[0], local: execArgs[1])
    default:
        print("""
        Usage:
          swift tools/ps4-linux-remote.swift setup [--host 10.0.1.7]
          swift tools/ps4-linux-remote.swift serve [--port 8766]
          swift tools/ps4-linux-remote.swift upload-bootstrap [--host 10.0.1.7]
          swift tools/ps4-linux-remote.swift probe | exec | push | pull
        Env: PS4_HOST, PS4_SSH_USER (default root)
        """)
    }
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}