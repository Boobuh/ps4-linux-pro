#!/usr/bin/env swift
// Remove stuck legacy PS4 Linux homebrew titles (CSTP00001/00002) over GoldHEN FTP.
// Keeps CSTP00003 as the single Library app; future PKGs update that title in place.
import Foundation

let legacyTitleIDs = ["CSTP00001", "CSTP00002"]
let keepTitleID = "CSTP00003"

struct Config {
    var host = ProcessInfo.processInfo.environment["PS4_HOST"] ?? "10.0.1.7"
    var port = 2121
}

@discardableResult
func runCurl(_ args: [String]) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    task.arguments = ["--connect-timeout", "15", "-m", "120", "-sS"] + args
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
    guard task.terminationStatus == 0 else {
        throw NSError(domain: "legacy-titles", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr])
    }
    return stdout + stderr
}

func ftpList(host: String, port: Int, path: String) throws -> [String] {
    let url = "ftp://\(host):\(port)\(path.hasSuffix("/") ? path : path + "/")"
    let body = try runCurl([url])
    var names: [String] = []
    for line in body.split(separator: "\n") {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9 else { continue }
        let name = String(parts[8...].joined(separator: " "))
        if name == "." || name == ".." { continue }
        names.append(name)
    }
    return names
}

func ftpQuote(_ host: String, _ port: Int, _ command: String) {
    do {
        _ = try runCurl(["-Q", command, "ftp://\(host):\(port)/"])
        print("  \(command)")
    } catch {
        print("  note: \(command) — \(error.localizedDescription)")
    }
}

func removeTitleDir(host: String, port: Int, titleID: String) throws {
    let base = "/user/app/\(titleID)"
    print("Cleaning \(base) …")
    let entries: [String]
    do {
        entries = try ftpList(host: host, port: port, path: base)
    } catch {
        print("  (no directory or empty: \(error.localizedDescription))")
        return
    }
    for name in entries {
        let childPath = "\(base)/\(name)"
        if name.contains(".") && !name.hasSuffix("/") {
            ftpQuote(host, port, "DELE \(childPath)")
        } else {
            // Nested dir — one level of children
            if let nested = try? ftpList(host: host, port: port, path: childPath) {
                for n2 in nested {
                    ftpQuote(host, port, "DELE \(childPath)/\(n2)")
                }
            }
            ftpQuote(host, port, "RMD \(childPath)")
        }
    }
    for name in entries {
        ftpQuote(host, port, "DELE \(base)/\(name)")
    }
    ftpQuote(host, port, "RMD \(base)")
}

func pruneAllLinuxPkgs(host: String, port: Int) throws {
    print("Removing all PS4 Linux PKGs from /data/pkg/ …")
    let list = try ftpList(host: host, port: port, path: "/data/pkg")
    for name in list where name.hasSuffix(".pkg") {
        let isOurs = name.contains("PS4-Linux-v") || name.contains("CSTP0000") || name.contains("PS4LINUX")
        if isOurs {
            ftpQuote(host, port, "DELE /data/pkg/\(name)")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
var cfg = Config()
var i = 0
while i < args.count {
    if args[i] == "--host", i + 1 < args.count {
        cfg.host = args[i + 1]
        i += 2
        continue
    }
    i += 1
}

let cmd = args.first ?? "help"

do {
    switch cmd {
    case "remove":
        print("=== Remove legacy titles (keep \(keepTitleID)) ===\n")
        for tid in legacyTitleIDs {
            try removeTitleDir(host: cfg.host, port: cfg.port, titleID: tid)
        }
        try pruneAllLinuxPkgs(host: cfg.host, port: cfg.port)
        print(
            """

            Done. If CSTP00001/00002 tiles still show in Library:
              Library → each old PS4 Linux → Options → Delete
            Then install only PS4-Linux-v*.pkg for CSTP00003 — later builds UPDATE that tile (same TITLE_ID).
            """
        )
    case "prune-pkgs":
        try pruneAllLinuxPkgs(host: cfg.host, port: cfg.port)
        print("Only upload the newest PS4-Linux-v*.pkg after this.")
    case "status":
        print("=== Title dirs on \(cfg.host) ===\n")
        for tid in legacyTitleIDs + [keepTitleID] {
            let base = "/user/app/\(tid)"
            if let entries = try? ftpList(host: cfg.host, port: cfg.port, path: base), !entries.isEmpty {
                print("\(tid): \(entries.count) entries")
            } else {
                print("\(tid): (absent or empty)")
            }
        }
    default:
        print(
            """
            Usage:
              swift tools/ps4-linux-legacy-titles.swift prune-pkgs [--host 10.0.1.7]
              swift tools/ps4-linux-legacy-titles.swift status [--host 10.0.1.7]
              swift tools/ps4-linux-legacy-titles.swift remove [--host 10.0.1.7]

            One Library app: \(keepTitleID). PKG updates replace it when APP_VER/VERSION rise.
            """
        )
        exit(cmd == "help" ? 0 : 1)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
