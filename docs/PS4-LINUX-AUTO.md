# PS4 internal Linux — automated (no rescue shell typing)

Mac prepares everything; on the PS4 use **Payload Guest** from the Library (see **`docs/PS4-LINUX-XMB-LAUNCH.md`**) — no Mac or USB on later boots.

## One command (PS4 on GoldHEN FTP, `10.0.1.7`)

```bash
cd /path/to/ps4-linux-pro
swift tools/ps4-linux-sync.swift sync --host 10.0.1.7 --install-gb 50
```

Or split: **`prepare`** (Mac only, no PS4) then **`upload`** when the console is on Orbis with FTP.

```bash
swift tools/ps4-linux-sync.swift prepare --install-gb 50
swift tools/ps4-linux-sync.swift upload --host 10.0.1.7
```

Set `PS4_HOST=10.0.1.7` to omit `--host`.

What it does:

1. Downloads **full** hippie68 `psxitarch.tar.xz` (~1.76 GB, SHA256 verified) if missing or corrupt.
2. Builds **auto-install** Nazky initramfs (`install-HDD.sh` runs itself when `Arch.img` is missing; size from `ps4-install-gb.txt`).
3. FTP: deletes broken **`/user/home/Arch.img`**, uploads `bzImage`, initramfs, **`arch.tar.xz`**, `vram.txt` (**1024**), payloads.

## On the console

1. **Unplug USB storage.**
2. **Library → PS4 Linux** → **Triangle** once: confirm **Baikal** detection, **Square** = apply recommended, **Cross** on **Save boot files**.
3. **Cross** on main screen to boot.
4. **Wait** — HDMI should show **Step 1/2/3 install text**; first install can take **30–90+ minutes**.

No `exec install-HDD.sh`, no `exec start-arch.sh` unless auto-boot fails (then **Ctrl+D** twice).

## Options

| Flag | Default | Meaning |
| --- | --- | --- |
| `--host` | `10.0.1.7` or `PS4_HOST` | FTP target |
| `--install-gb` | `50` | Written to `/user/system/boot/ps4-install-gb.txt` (minimum 50) |

## First-time note

`initramfs.nazky.cpio.gz` must exist under `downloads/ps4-linux-baikal/` (already in repo from Mega). Sync copies it if only `initramfs.cpio.gz` is present.
