# Cursor chat archive (from `cursor-setup`)

Cursor ties **chat sidebar history to the workspace folder**, not the git remote. This directory keeps the PS4 Linux work readable in **ps4-linux-pro** and on GitHub.

| File | Purpose |
|------|---------|
| [CHAT-SNAPSHOT-20261124.md](CHAT-SNAPSHOT-20261124.md) | **Latest save** — paths + recovery steps (oleh → Apple / other user) |
| [raw/0c7210df-503f-412a-bf5b-d986db64b793-thread.jsonl](raw/0c7210df-503f-412a-bf5b-d986db64b793-thread.jsonl) | Main Android TV / Baikal thread (JSONL, ~913 KiB, Nov 2026) |
| [PS4-ANDROID-TV-CURSOR-THREAD.md](PS4-ANDROID-TV-CURSOR-THREAD.md) | Markdown export of that thread (read in any editor) |
| [raw/bc0c13b6-cursor-setup-thread.jsonl](raw/bc0c13b6-cursor-setup-thread.jsonl) | Full agent transcript (JSONL, same format Cursor uses under `~/.cursor/projects/…/agent-transcripts/`) |
| [PS4-LINUX-THREAD.md](PS4-LINUX-THREAD.md) | Markdown export from the first PS4 Linux message through the end of the thread |
| [ARCHIVE.md](ARCHIVE.md) | Full thread as markdown (includes non–PS4 topics from the same composer) |
| [attachments/](attachments/) | Small attachment files referenced in that thread |

Composer ids:
- **`0c7210df-503f-412a-bf5b-d986db64b793`** — PS4 Linux + Android TV Baikal (active thread; see snapshot above)
- **`bc0c13b6-bead-4a8f-978b-45a231b3c41e`** — started on `cursor-setup`, title still shows as *DualSense compatibility with Torchlight 2* in Cursor search

**Refresh repo copy from live Cursor (oleh):**

```bash
cp -f ~/.cursor/projects/Users-Shared-dev-ps4-linux-pro/agent-transcripts/0c7210df-503f-412a-bf5b-d986db64b793/0c7210df-503f-412a-bf5b-d986db64b793.jsonl \
  docs/cursor-chats/raw/0c7210df-503f-412a-bf5b-d986db64b793-thread.jsonl
```

## Restore chats in the Cursor sidebar

1. Open **`/Users/Shared/dev/ps4-linux-pro`** in Cursor (creates the workspace entry).
2. Run:

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift install-local
```

3. **Developer: Reload Window** if the old thread does not appear immediately.

`install-local` also re-homes the archived composer from **cursor-setup** to this folder in Cursor’s global DB (`workspaceIdentifier`). Without that step the sidebar stays empty even when the jsonl copy succeeds.

If the list is still empty after reload, copy the working **cursor-setup** workspace composer state:

```bash
swift tools/ps4-linux-cursor-chats-migrate.swift copy-workspace-from-setup
```

(Quitting Cursor first avoids SQLite WAL fighting the copy.)

Check wiring:

```bash
swift tools/ps4-linux-cursor-chats-migrate.swift status
```

Agents in this repo should search **`docs/cursor-chats/PS4-LINUX-THREAD.md`** (or the raw JSONL) for prior decisions, PKG versions, and PS4 FTP paths.

## Chats started as macOS user **Apple** (admin)

Cursor keeps **separate** profiles per macOS user (`/Users/Shared/IT/README-cursor-dual-macos-user.md`).  
`oleh` cannot read `dot-cursor-Apple` directly (permissions).

1. Quit Cursor on both macOS users if possible.
2. Export transcripts into the repo (shared staging, no SQLite merge).

As **Apple** (fast user switch):

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift export-from-apple
```

Or stay on **oleh** and use admin `sudo` (your Mac login password — not the word “Administrator”):

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift export-from-apple --sudo
```

3. Switch back to **oleh**. **Quit Cursor (Cmd+Q)** on both users for SQLite merge.

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift import-from-apple-staging
swift tools/ps4-linux-cursor-chats-migrate.swift export-sqlite-from-apple --sudo
swift tools/ps4-linux-cursor-chats-migrate.swift import-sqlite-from-apple-staging
swift tools/ps4-linux-cursor-chats-migrate.swift status
```

Jsonl alone does **not** fill the sidebar; you need **`composerData` / `composerHeader` / bubbles** in global `state.vscdb` from the Apple profile (`export-sqlite-from-apple`).

4. **Hydrate message list** (Cursor 3.x uses `composerConvHeaders:*` + `composerHeaders` table — not `conversationMap` on disk):

```bash
swift tools/ps4-linux-cursor-chats-migrate.swift hydrate-composers
```

5. **Cmd+Q** Cursor (full quit), reopen this repo, open the thread in the **Agent** sidebar (e.g. “PS4 Linux cursor migration”).

If the pane is **still empty**, Apple’s Agent threads cannot be replayed from copied SQLite alone (`conversationState` is opaque). Rebuild readable UI state from jsonl (same fix as lkq-be Ubuntu import):

```bash
cd /Users/Shared/dev/ps4-linux-pro
python3 tools/ps4-linux-cursor-rebuild-from-jsonl.py --apply
```

Backup lands under `tmp/backups/cursor-globalStorage-jsonl-rebuild-*`.

**Read-only fallback:** `docs/cursor-chats/PS4-LINUX-THREAD.md`, `ARCHIVE.md`, and `docs/cursor-chats/raw/*.jsonl`.
