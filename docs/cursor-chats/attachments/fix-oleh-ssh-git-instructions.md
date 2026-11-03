# Fix Git/SSH for user `oleh` (run as macOS user **Apple**)

## Problem

When **oleh** runs `git fetch`, `git push`, or `ssh`:

```text
Bad owner or permissions on /Users/oleh/.ssh/config
```

**Cause:** `/Users/oleh/.ssh/config` (and often `known_hosts`) are owned by **Apple** with mode `644`. OpenSSH requires the config to be owned by the connecting user and mode **600**. Only **Apple** (or root) can change that because of file ACLs.

## One-time fix (Apple user + sudo)

1. Log in to macOS as **Apple** (not `oleh`).
2. Open **Terminal**.
3. Run **either** the script **or** the commands below.

### Option A — script (recommended)

```bash
sudo /Users/Shared/IT/fix-oleh-ssh-config-permissions.sh oleh
```

### Option B — manual commands

```bash
sudo chown oleh:staff /Users/oleh/.ssh/config /Users/oleh/.ssh/known_hosts
sudo chmod 600 /Users/oleh/.ssh/config /Users/oleh/.ssh/known_hosts
ls -la /Users/oleh/.ssh/config /Users/oleh/.ssh/known_hosts
```

Expected:

```text
-rw-------  1 oleh  staff  ... config
-rw-------  1 oleh  staff  ... known_hosts
```

4. Log back in as **oleh**.

## Verify as `oleh`

```bash
cd /Users/Shared/dev/lkq-be
git fetch origin
```

No `Bad owner or permissions` error.

Optional:

```bash
ssh -T git@gitlab.carsys.online
```

## Temporary workaround (if sudo not done yet)

As **oleh**, use the repo wrapper (bypasses broken `~/.ssh/config`):

```bash
/Users/Shared/dev/lkq-be/tmp/scripts/git-with-oleh-ssh.sh -C /Users/Shared/dev/lkq-be fetch origin
```

Uses `~/.ssh/config.oleh` and `~/.ssh/known_hosts.oleh` (oleh-owned). Remove reliance on this after the one-time fix above.

## Prevent recurrence

- Do not create or edit `~oleh/.ssh/*` while logged in as **Apple**.
- Quit Cursor / terminals before fast-user-switching; see `/Users/Shared/IT/README-cursor-dual-macos-user.md`.
- Per-user Cursor trees: `Cursor-oleh` vs `Cursor-Apple` — do not share one profile.

## Files in this folder

| File | Purpose |
|------|---------|
| `fix-oleh-ssh-config-permissions.sh` | `sudo` repair script |
| `fix-oleh-ssh-git-instructions.md` | This document |
| `README-cursor-dual-macos-user.md` | Cursor dual-user layout |
