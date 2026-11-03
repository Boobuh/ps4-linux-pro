# Cursor chat archive (from `cursor-setup`)

Cursor ties **chat sidebar history to the workspace folder**, not the git remote. This directory keeps the PS4 Linux work readable in **ps4-linux-pro** and on GitHub.

| File | Purpose |
|------|---------|
| [raw/bc0c13b6-cursor-setup-thread.jsonl](raw/bc0c13b6-cursor-setup-thread.jsonl) | Full agent transcript (JSONL, same format Cursor uses under `~/.cursor/projects/…/agent-transcripts/`) |
| [PS4-LINUX-THREAD.md](PS4-LINUX-THREAD.md) | Markdown export from the first PS4 Linux message through the end of the thread |
| [ARCHIVE.md](ARCHIVE.md) | Full thread as markdown (includes non–PS4 topics from the same composer) |
| [attachments/](attachments/) | Small attachment files referenced in that thread |

Composer id: `bc0c13b6-bead-4a8f-978b-45a231b3c41e` (started on `cursor-setup`, title still shows as *DualSense compatibility with Torchlight 2* in Cursor search).

## Restore chats in the Cursor sidebar

1. Open **`/Users/Shared/dev/ps4-linux-pro`** in Cursor (creates the workspace entry).
2. Run:

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift install-local
```

3. **Developer: Reload Window** if the old thread does not appear immediately.

Check wiring:

```bash
swift tools/ps4-linux-cursor-chats-migrate.swift status
```

Agents in this repo should search **`docs/cursor-chats/PS4-LINUX-THREAD.md`** (or the raw JSONL) for prior decisions, PKG versions, and PS4 FTP paths.
