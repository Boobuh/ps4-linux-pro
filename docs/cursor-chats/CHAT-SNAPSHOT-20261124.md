# Chat snapshot — 2026-11-24

Saved from macOS user **oleh** for recovery on **Apple** (or any user) on this Mac.

## Primary thread (this session arc)

| Item | Path |
|------|------|
| Full transcript (JSONL) | [raw/0c7210df-503f-412a-bf5b-d986db64b793-thread.jsonl](raw/0c7210df-503f-412a-bf5b-d986db64b793-thread.jsonl) |
| Readable export | [PS4-ANDROID-TV-CURSOR-THREAD.md](PS4-ANDROID-TV-CURSOR-THREAD.md) |
| Staging copy (import) | `staging/from-Apple/agent-transcripts/0c7210df-503f-412a-bf5b-d986db64b793/` |

Composer id: `0c7210df-503f-412a-bf5b-d986db64b793`  
Workspace: `/Users/Shared/dev/ps4-linux-pro`

Topics in this thread include: PS4 Linux, Android TV on Baikal Pro, white-light freeze, unit tests, PKG upload (`Android-TV-baikal-white-light-retest.pkg`), build/repack fixes.

## Other archived threads

| Composer | JSONL |
|----------|--------|
| `bc0c13b6-bead-4a8f-978b-45a231b3c41e` | [raw/bc0c13b6-cursor-setup-thread.jsonl](raw/bc0c13b6-cursor-setup-thread.jsonl) |
| `a98e44e9-6539-4ecd-9635-10ae96c670ac` | [raw/a98e44e9-6539-4ecd-9635-10ae96c670ac-thread.jsonl](raw/a98e44e9-6539-4ecd-9635-10ae96c670ac-thread.jsonl) |

Earlier PS4 Linux markdown: [PS4-LINUX-THREAD.md](PS4-LINUX-THREAD.md)

## Restore into Cursor sidebar (other macOS user)

1. Open **`/Users/Shared/dev/ps4-linux-pro`** in Cursor (quit Cursor first if importing SQLite).
2. As the **target** user:

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-cursor-chats-migrate.swift import-from-apple-staging
```

(Staging already contains the latest `0c7210df` jsonl from this save.)

3. If the thread list is empty or messages don’t show:

```bash
swift tools/ps4-linux-cursor-chats-migrate.swift hydrate-composers
python3 tools/ps4-linux-cursor-rebuild-from-jsonl.py --apply
```

4. **Cmd+Q** Cursor, reopen the repo, open the thread in the Agent sidebar.

**Read-only:** open `PS4-ANDROID-TV-CURSOR-THREAD.md` or the raw JSONL in any editor — no Cursor import required.