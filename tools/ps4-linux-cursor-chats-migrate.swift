#!/usr/bin/env swift
// Links archived Cursor chats to the ps4-linux-pro workspace and refreshes repo exports.
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let rawTranscript = repoRoot
    .appendingPathComponent("docs/cursor-chats/raw/bc0c13b6-cursor-setup-thread.jsonl")
let composerID = "bc0c13b6-bead-4a8f-978b-45a231b3c41e"
let cursorProjectSlug = "Users-Shared-dev-ps4-linux-pro"
let workspaceFolder = "file:///Users/Shared/dev/ps4-linux-pro"

struct ComposerMeta: Codable {
    var selectedComposerIds: [String]
    var lastFocusedComposerIds: [String]
    var hasMigratedComposerData: Bool?
    var hasMigratedMultipleComposers: Bool?
}

func usage() -> Never {
    let me = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ps4-linux-cursor-chats-migrate.swift"
    fputs(
        """
        Usage:
          swift tools/\(me) install-local
            Copy agent transcript into ~/.cursor/projects/\(cursorProjectSlug)/
            and register composer \(composerID) on the ps4-linux-pro workspace (open folder once first).

          swift tools/\(me) status
            Show whether local Cursor project + workspace DB are wired.

        Archived chats live under docs/cursor-chats/ (also in git).
        Cursor does not import sidebar history from git alone — run install-local after opening this repo.

        """,
        stderr
    )
    exit(1)
}

func homeCursorProjects() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/projects/\(cursorProjectSlug)", isDirectory: true)
}

func copyTranscript(to projectDir: URL) throws {
    let destDir = projectDir
        .appendingPathComponent("agent-transcripts/\(composerID)", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    let destFile = destDir.appendingPathComponent("\(composerID).jsonl")
    if FileManager.default.fileExists(atPath: destFile.path) {
        try FileManager.default.removeItem(at: destFile)
    }
    try FileManager.default.copyItem(at: rawTranscript, to: destFile)
}

func workspaceStorageRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
}

func findWorkspaceDB(for folderURI: String) -> URL? {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: workspaceStorageRoot(),
        includingPropertiesForKeys: nil
    ) else { return nil }
    for entry in entries {
        let ws = entry.appendingPathComponent("workspace.json")
        guard let data = try? Data(contentsOf: ws),
              let text = String(data: data, encoding: .utf8),
              text.contains(folderURI)
        else { continue }
        return entry.appendingPathComponent("state.vscdb")
    }
    return nil
}

@discardableResult
func runShell(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, text)
    } catch {
        return (127, "\(error)")
    }
}

func patchComposerData(db: URL) -> Bool {
    let (readStatus, existing) = runShell("/usr/bin/sqlite3", [db.path, "SELECT value FROM ItemTable WHERE key='composer.composerData';"])
    guard readStatus == 0 else { return false }

    let meta: ComposerMeta
    if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        meta = ComposerMeta(
            selectedComposerIds: [composerID],
            lastFocusedComposerIds: [composerID],
            hasMigratedComposerData: true,
            hasMigratedMultipleComposers: true
        )
    } else if let data = existing.data(using: .utf8),
              var decoded = try? JSONDecoder().decode(ComposerMeta.self, from: data) {
        if !decoded.selectedComposerIds.contains(composerID) {
            decoded.selectedComposerIds.insert(composerID, at: 0)
        }
        if !decoded.lastFocusedComposerIds.contains(composerID) {
            decoded.lastFocusedComposerIds.insert(composerID, at: 0)
        }
        decoded.hasMigratedComposerData = true
        decoded.hasMigratedMultipleComposers = true
        meta = decoded
    } else {
        meta = ComposerMeta(
            selectedComposerIds: [composerID],
            lastFocusedComposerIds: [composerID],
            hasMigratedComposerData: true,
            hasMigratedMultipleComposers: true
        )
    }

    guard let encoded = try? JSONEncoder().encode(meta),
          let json = String(data: encoded, encoding: .utf8)
    else { return false }

    let sql = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('composer.composerData', '\(json.replacingOccurrences(of: "'", with: "''"))');"
    let (writeStatus, _) = runShell("/usr/bin/sqlite3", [db.path, sql])
    return writeStatus == 0
}

func cmdStatus() {
    let projectDir = homeCursorProjects()
    let transcript = projectDir
        .appendingPathComponent("agent-transcripts/\(composerID)/\(composerID).jsonl")
    print("repo raw transcript:", rawTranscript.path, FileManager.default.fileExists(atPath: rawTranscript.path) ? "ok" : "MISSING")
    print("local agent transcript:", transcript.path, FileManager.default.fileExists(atPath: transcript.path) ? "ok" : "missing")
    if let db = findWorkspaceDB(for: workspaceFolder) {
        print("workspace state.vscdb:", db.path, "found")
        let (_, value) = runShell("/usr/bin/sqlite3", [db.path, "SELECT value FROM ItemTable WHERE key='composer.composerData';"])
        print("composer.composerData:", value.trimmingCharacters(in: .whitespacesAndNewlines))
    } else {
        print("workspace state.vscdb: not found — open \(repoRoot.path) in Cursor once, then re-run install-local")
    }
}

func cmdInstallLocal() throws {
    guard FileManager.default.fileExists(atPath: rawTranscript.path) else {
        fputs("Missing \(rawTranscript.path)\n", stderr)
        exit(1)
    }
    let projectDir = homeCursorProjects()
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try copyTranscript(to: projectDir)
    print("Copied agent transcript → \(projectDir.path)")

    if let db = findWorkspaceDB(for: workspaceFolder) {
        if patchComposerData(db: db) {
            print("Updated composer.composerData in \(db.path)")
            print("Reload Cursor window (Developer: Reload Window) if the chat list is still empty.")
        } else {
            fputs("Could not update composer.composerData\n", stderr)
            exit(1)
        }
    } else {
        print("Workspace DB not created yet. Open this repo in Cursor, then run install-local again.")
    }
}

guard CommandLine.arguments.count >= 2 else { usage() }
switch CommandLine.arguments[1] {
case "install-local":
    do { try cmdInstallLocal() } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
case "status":
    cmdStatus()
default:
    usage()
}
