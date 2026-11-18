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
let workspaceFolderPath = "/Users/Shared/dev/ps4-linux-pro"
let setupWorkspaceFolder = "file:///Users/Shared/dev/cursor-setup"
let setupCursorProjectSlug = "Users-Shared-dev-cursor-setup"

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

          swift tools/\(me) copy-workspace-from-setup
            Copy composer sidebar state from the cursor-setup workspace into ps4-linux-pro
            (workspaceStorage composer keys + agent-transcripts, re-home composer ids).

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

func globalStorageDB() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
}

func findWorkspaceDB(for folderURI: String) -> (db: URL, storageId: String)? {
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
        return (entry.appendingPathComponent("state.vscdb"), entry.lastPathComponent)
    }
    return nil
}

/// Cursor lists chats per workspace; archived threads from cursor-setup must be re-homed here.
func patchGlobalComposerWorkspace(storageId: String) -> Bool {
    let db = globalStorageDB()
    guard FileManager.default.fileExists(atPath: db.path) else { return false }

    // composerData JSON is large; sqlite3 CLI quoting can hang — use Python + busy_timeout.
    let py = """
    import json, sqlite3, sys
    db, cid, sid, folder, uri = sys.argv[1:6]
    conn = sqlite3.connect(db, timeout=30)
    conn.execute("PRAGMA busy_timeout=30000")
    key = f"composerData:{cid}"
    row = conn.execute("SELECT value FROM cursorDiskKV WHERE key=?", (key,)).fetchone()
    if not row:
        sys.exit(1)
    doc = json.loads(row[0])
    doc["workspaceIdentifier"] = {
        "id": sid,
        "uri": {"$mid": 1, "fsPath": folder, "external": uri, "path": folder, "scheme": "file"},
    }
    conn.execute(
        "INSERT OR REPLACE INTO cursorDiskKV (key, value) VALUES (?, ?)",
        (key, json.dumps(doc, separators=(",", ":"))),
    )
    conn.commit()
    """
    let (status, _) = runShell(
        "/usr/bin/python3",
        ["-c", py, db.path, composerID, storageId, workspaceFolderPath, workspaceFolder]
    )
    return status == 0
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
    if let ws = findWorkspaceDB(for: workspaceFolder) {
        print("workspace state.vscdb:", ws.db.path, "found (id \(ws.storageId))")
        let (_, value) = runShell("/usr/bin/sqlite3", [ws.db.path, "SELECT value FROM ItemTable WHERE key='composer.composerData';"])
        print("composer.composerData:", value.trimmingCharacters(in: .whitespacesAndNewlines))
    } else {
        print("workspace state.vscdb: not found — open \(repoRoot.path) in Cursor once, then re-run install-local")
    }

    let globalDB = globalStorageDB()
    let py = """
    import json, sqlite3, sys
    db, cid = sys.argv[1], sys.argv[2]
    conn = sqlite3.connect(db, timeout=5)
    row = conn.execute("SELECT value FROM cursorDiskKV WHERE key=?", (f"composerData:{cid}",)).fetchone()
    if not row:
        print("missing")
    else:
        wid = json.loads(row[0]).get("workspaceIdentifier") or {}
        print(wid.get("id", "nil"))
    """
    let (_, widOut) = runShell("/usr/bin/python3", ["-c", py, globalDB.path, composerID])
    print("global workspaceIdentifier.id:", widOut.trimmingCharacters(in: .whitespacesAndNewlines))
}

func cmdCopyWorkspaceFromSetup() throws {
    guard let setupWS = findWorkspaceDB(for: setupWorkspaceFolder),
          let ps4WS = findWorkspaceDB(for: workspaceFolder)
    else {
        fputs("Open cursor-setup and ps4-linux-pro in Cursor once so both workspace DBs exist.\n", stderr)
        exit(1)
    }

    let py = """
    import json, sqlite3, shutil, sys
    from pathlib import Path

    setup_db, ps4_db, global_db = map(Path, sys.argv[1:4])
    ps4_id, ps4_folder, ps4_uri = sys.argv[4:7]
    setup_transcripts, ps4_transcripts = map(Path, sys.argv[7:9])

    force_keys = [
        "composer.composerData",
        "workbench.parts.embeddedAuxBarEditor.state",
        "workbench.backgroundComposer.workspacePersistentData",
    ]

    def connect(path):
        conn = sqlite3.connect(path, timeout=30)
        conn.execute("PRAGMA busy_timeout=30000")
        return conn

    setup_c = connect(setup_db)
    ps4_c = connect(ps4_db)
    copied = []
    for key in force_keys:
        row = setup_c.execute("SELECT value FROM ItemTable WHERE key=?", (key,)).fetchone()
        if not row:
            continue
        val = row[0]
        if key == "workbench.backgroundComposer.workspacePersistentData":
            val = val.replace("/Users/Shared/dev/cursor-setup", ps4_folder)
        ps4_c.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, val))
        copied.append(key)

    for row in setup_c.execute(
        "SELECT key, value FROM ItemTable WHERE value LIKE ? OR value LIKE ?",
        ("%bc0c13b6-bead-4a8f-978b-45a231b3c41e%", "%a98e44e9-6539-4ecd-9635-10ae96c670ac%"),
    ):
        key, val = row
        if key in copied:
            continue
        val = val.replace("/Users/Shared/dev/cursor-setup", ps4_folder)
        ps4_c.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, val))
        copied.append(key)
    ps4_c.commit()

    meta = json.loads(
        ps4_c.execute("SELECT value FROM ItemTable WHERE key='composer.composerData'").fetchone()[0]
    )
    composer_ids = list(
        dict.fromkeys(meta.get("selectedComposerIds", []) + meta.get("lastFocusedComposerIds", []))
    )
    g = connect(global_db)
    wid = {
        "id": ps4_id,
        "uri": {
            "$mid": 1,
            "fsPath": ps4_folder,
            "external": ps4_uri,
            "path": ps4_folder,
            "scheme": "file",
        },
    }
    for cid in composer_ids:
        key = f"composerData:{cid}"
        row = g.execute("SELECT value FROM cursorDiskKV WHERE key=?", (key,)).fetchone()
        if not row:
            continue
        doc = json.loads(row[0])
        doc["workspaceIdentifier"] = wid
        g.execute(
            "INSERT OR REPLACE INTO cursorDiskKV (key, value) VALUES (?, ?)",
            (key, json.dumps(doc, separators=(",", ":"))),
        )
    g.commit()
    print("copied", len(copied), "workspace keys; re-homed", len(composer_ids), "composers")

    if setup_transcripts.is_dir():
        ps4_transcripts.mkdir(parents=True, exist_ok=True)
        for child in setup_transcripts.iterdir():
            dest = ps4_transcripts / child.name
            if child.is_dir():
                shutil.copytree(child, dest, dirs_exist_ok=True)
            else:
                shutil.copy2(child, dest)
    """
    let setupTranscripts = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/projects/\(setupCursorProjectSlug)/agent-transcripts", isDirectory: true)
    let ps4Transcripts = homeCursorProjects().appendingPathComponent("agent-transcripts", isDirectory: true)

    let (status, out) = runShell(
        "/usr/bin/python3",
        [
            "-c", py,
            setupWS.db.path,
            ps4WS.db.path,
            globalStorageDB().path,
            ps4WS.storageId,
            workspaceFolderPath,
            workspaceFolder,
            setupTranscripts.path,
            ps4Transcripts.path,
        ]
    )
    print(out.trimmingCharacters(in: .whitespacesAndNewlines))
    guard status == 0 else {
        fputs("copy-workspace-from-setup failed\n", stderr)
        exit(1)
    }
    print("Reload Cursor window (Developer: Reload Window). Quit Cursor first if the list still ignores the copy.")
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

    if let ws = findWorkspaceDB(for: workspaceFolder) {
        if patchGlobalComposerWorkspace(storageId: ws.storageId) {
            print("Re-homed global composerData workspaceIdentifier → \(ws.storageId) (\(workspaceFolderPath))")
        } else {
            fputs("Warning: could not update global composerData workspaceIdentifier (chat may stay on cursor-setup)\n", stderr)
        }
        if patchComposerData(db: ws.db) {
            print("Updated composer.composerData in \(ws.db.path)")
        } else {
            fputs("Could not update composer.composerData\n", stderr)
            exit(1)
        }
        print("Reload Cursor window (Developer: Reload Window) if the chat list is still empty.")
        print("If a thread appears but will not open, read docs/cursor-chats/README.md (Cursor 3.x composer hydration).")
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
case "copy-workspace-from-setup":
    do { try cmdCopyWorkspaceFromSetup() } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
default:
    usage()
}
