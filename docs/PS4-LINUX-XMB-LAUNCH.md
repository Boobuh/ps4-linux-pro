# Launch PS4 Linux from the home screen (no Mac, no USB)

Use the **PS4 Linux** homebrew PKG — a dedicated app, not Payload Guest.

Full build/install: **`docs/PS4-LINUX-LOADER-PKG.md`**

## Quick path

1. **Mac (once):** `swift tools/ps4-linux-launcher-build.swift` → install PKG via FTP  
2. **Mac (once):** `swift tools/ps4-linux-sync.swift sync` → boot files + payloads on internal HDD  
3. **PS4:** Package Installer → **PS4 Linux**  
4. **Every boot:** GoldHEN → **Library → PS4 Linux** → **Cross** (USB storage unplugged)

Sync uploads the latest **`PS4-Linux-v*.pkg`** to **`/data/pkg/`** when present.

---

## Legacy: Payload Guest

Still works with **`meta.json`** + **`linux-1024mb.bin`** if you prefer Al-Azif’s app — see git history of this file.
