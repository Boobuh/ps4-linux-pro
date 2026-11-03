# PS4 Linux — standalone homebrew PKG

Dedicated **Library** app (not Payload Guest): **PS4 Linux** loads the **ps4-linux-loader** kexec payload from internal storage and boots **`/data/linux/boot/`** (Baikal Pro internal Linux stack).

**Pre-release line:** semantic **v0.7.x** in the UI; Sony **`param.sfo`** bumps **`APP_VER`** (`00.70`, `00.71`, …) **and** **`VERSION`** (`01.70`, `01.71`, … from the build counter). Both must rise each build — keeping **`VERSION` stuck at `01.00`** made GoldHEN treat every PKG as the same revision even when **`APP_VER`** changed.

## Build the PKG (Mac, once)

Prerequisites:

1. **LLVM** with PS4 target — `brew install llvm` (Apple Silicon: `/opt/homebrew/opt/llvm/bin/clang`)
2. OpenOrbis toolchain — downloaded automatically on first build

```bash
cd /path/to/ps4-linux-pro
swift tools/ps4-linux-launcher-build.swift          # bumps 0.7.x + APP_VER
swift tools/ps4-linux-launcher-build.swift --no-bump   # rebuild without bumping
```

Output (human-readable — use this in Package Installer):

`ps4-linux-launcher-app/linux-loader/PS4-Linux-v0.7.5-b75-APP0075.pkg`

Pattern: **`PS4-Linux-v{semver}-b{build}-APP{sonyAppVer}.pkg`** (e.g. `APP0075` = param.sfo **00.75**). OpenOrbis also writes **`IV0000-CSTP00002_00-PS4LINUXL0700000.pkg`** (same bytes; ignore for install).

Or install [OpenOrbis PS4 Toolchain macOS PKG](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain/releases) and set `OO_PS4_TOOLCHAIN`, then `make -C ps4-linux-launcher-app/linux-loader`.

**Tests (Mac):** `swift tools/ps4-linux-test.swift` — see [PS4-LINUX-TESTING.md](PS4-LINUX-TESTING.md).

## Install + run on PS4

1. **`swift tools/ps4-linux-sync.swift sync`** — kernel, initramfs, **`arch.tar.xz`**, **`linux-1024mb.bin`**
2. FTP the built **`*.pkg`** → **`/data/pkg/`** (sync uploads it when present)
3. **GoldHEN → Debug Settings → Package Installer**
   - **Disable “Enable Background Installation”** — if this stays on, GoldHEN often reports **Package already installed** and never offers overwrite ([community fix](https://www.reddit.com/r/ps4homebrew/comments/1qhq67v/goldhen_package_already_installed/)).
   - **Package Source:** `Hdd [hdd:/data/pkg/]` (or All)
4. Install the **`PS4-Linux-v*.pkg`** file from **`/data/pkg/`** (pick the highest **APP** number in the filename).

**If Package Installer says “already installed”** — delete once, then install (GoldHEN quirk, not you):

1. **Library → PS4 Linux → Options → Delete** (confirm). Also delete old **`CSTP00001`** tile if it still exists.
2. Package Installer → **Background Installation OFF**, source **Hdd** `/data/pkg/`.
3. Install the PKG again. Latest build shows **v0.7.x** and **APP 00.xx** in the in-app footer.

5. **Library → PS4 Linux** → **Cross** to boot; **Triangle** for settings.

### Why “already installed” happened before

| Issue | Fix |
| --- | --- |
| **`APP_VER` missing** | 8-char values do not fit **`param.sfo`**; toolchain dropped **`APP_VER`** |
| **`VERSION` never bumped** | Installer saw same master revision (`01.00`) every time — now **`VERSION=01.{build}`** per Mac build |
| **Semver in `VERSION`** | Use Sony-style fields; **`APP_VER`** stays **`XX.YY`** (7 chars max) |
| **GoldHEN background install** | Turn off in Debug Settings (above) |
| **Ghost `CSTP00001` entry** | New pre-release ID **`CSTP00002`** + delete old tile if needed |

During first boot, HDMI should show **install step text** (not a blank blue screen). Progress is also logged to **`/user/system/boot/install-status.txt`** (FTP while on GoldHEN).

## What the app does

- Verifies **`/data/linux/boot/bzImage`** + **`initramfs.cpio.gz`**
- Picks loader: **`linux-1024mb.bin`** → **`payload-1100-1gb-pro-baikal.bin`** → **`linux-1024mb.elf`**
- Launch order (same as Payload Guest): Mira **9021** → GoldHEN **9090** → in-process shellcode

Not Android TV / not BinLoader-only — classic **ps4-linux-loader** path.

## Icon art

Library tile uses **`sce_sys/icon0.png`** (512×512). Source: [Wikimedia — Tux](https://commons.wikimedia.org/wiki/File:Tux.png) (Larry Ewing, GPL). **`pic0.png` / `pic1.png`** and in-app **`assets/images/Logo.png`** use the same mascot on black.

## Debug log (FTP)

The app appends errors and key events to **`/user/app/CSTP00002/ps4-linux-app.log`** first (title install dir, GoldHEN FTP), then **`/user/.ps4-linux-app.log`**, **`/user/data/ps4-linux-app.log`**, **`/data/pkg/ps4-linux-app.log`**. The **eboot** chain also writes **`eboot: …`** lines before **`guest.elf`** starts — if you only see eboot lines, **`LoadExec`** failed.

## Source

`ps4-linux-launcher-app/linux-loader/` — fork of [ps4-payload-guest](https://github.com/Al-Azif/ps4-payload-guest) (GPL-3.0), view replaced by **`LinuxLoaderView`**.

## IDs (pre-release 0.7)

| | |
| --- | --- |
| TITLE_ID | `CSTP00002` |
| CONTENT_ID | `IV0000-CSTP00002_00-PS4LINUXL0700000` |
| Legacy (remove from Library) | `CSTP00001` / `IV0000-CSTP00001_00-PS4LINUXLDR00000` |
