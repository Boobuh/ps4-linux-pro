# PS4 Linux — standalone homebrew PKG

Dedicated **Library** app (not Payload Guest): **PS4 Linux** loads the **ps4-linux-loader** kexec payload from internal storage and boots **`/data/linux/boot/`** (Baikal Pro internal Linux stack).

**Pre-release line:** semantic **v0.7.x** in the UI; Sony **`param.sfo`** bumps each build. Builds **70–79** use **`APP_VER=00.xx`** + **`VERSION=01.xx`**. From build **80+**, **`APP_VER=01.xx`** and **`VERSION=02.xx`** so GoldHEN accepts updates over **`00.79`** installs.

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

Pattern: **`PS4-Linux-v{semver}-b{build}-APP{sonyAppVer}.pkg`**. Canonical title **`CSTP00003`** only — one Library tile; each Mac build **updates** that title (same `TITLE_ID`, higher `APP_VER` / `VERSION`). Do not install older **`CSTP00002`** PKGs (different app id = duplicate tile).

OpenOrbis also writes **`IV0000-CSTP00003_00-PS4LINUXL0700001.pkg`** (same bytes as the versioned name).

Or install [OpenOrbis PS4 Toolchain macOS PKG](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain/releases) and set `OO_PS4_TOOLCHAIN`, then `make -C ps4-linux-launcher-app/linux-loader`.

**Tests (Mac):** `swift tools/ps4-linux-test.swift` — see [PS4-LINUX-TESTING.md](PS4-LINUX-TESTING.md). Layout regressions (CE-41839-5, truncated guest): [PS4-LINUX-PKG-POSTMORTEM.md](PS4-LINUX-PKG-POSTMORTEM.md).

## Install + run on PS4

1. **`swift tools/ps4-linux-sync.swift sync`** — kernel, initramfs, **`arch.tar.xz`**, **`linux-1024mb.bin`** (see **`docs/PS4-LINUX-BAIKAL-ASSETS.md`**)
2. If loaders were ELF misnamed `.bin`: **`swift tools/ps4-linux-sync.swift payloads`**
3. FTP the built **`*.pkg`** → **`/data/pkg/`** (sync uploads it when present)
4. **GoldHEN → Debug Settings → Package Installer**
   - **Disable “Enable Background Installation”** — if this stays on, GoldHEN often reports **Package already installed** and never offers overwrite ([community fix](https://www.reddit.com/r/ps4homebrew/comments/1qhq67v/goldhen_package_already_installed/)).
   - **Package Source:** `Hdd [hdd:/data/pkg/]` (or All)
5. Install the newest **`PS4-Linux-v*.pkg`** for **`CSTP00003`** from **`/data/pkg/`** (highest **APP** in the filename).

**One Library app:** only **`CSTP00003`**. Older **`CSTP00002`** / **`CSTP00001`** were broken update paths — remove them so you do not get two tiles:

```bash
swift tools/ps4-linux-legacy-titles.swift remove --host 10.0.1.7
```

Then **Library → Delete** any ghost **PS4 Linux** tiles that remain. After that, each new PKG **replaces** **`CSTP00003`** (Package Installer update), not a second copy.

**If Package Installer says “already installed” on `CSTP00003`:** Background Installation must be **OFF**, and the PKG **`APP_VER`** must be higher than what is installed (check footer in-app or reinstall after `legacy-titles remove`).

5. **Library → PS4 Linux** → **Cross** to boot; **Triangle** for settings.

### Why “already installed” happened before

| Issue | Fix |
| --- | --- |
| **`APP_VER` missing** | 8-char values do not fit **`param.sfo`**; toolchain dropped **`APP_VER`** |
| **`VERSION` never bumped** | Installer saw same master revision (`01.00`) every time — now **`VERSION`** tracks build (**`02.xx`** from build 80+) |
| **`00.80` not over `00.79`** | From build 80+, **`APP_VER`** uses **`01.xx`** (not **`00.xx`**) for clearer GoldHEN upgrade |
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

The app appends errors and key events to **`/user/app/CSTP00003/ps4-linux-app.log`** first, then **`/data/linux/boot/ps4-linux-app.log`**, **`/user/data/ps4-linux-app.log`**. Look for **`app: guest main entered`**. **`eboot:`** lines only → **`LoadExec`** did not hand off.

## Source

**Layout (v0.7.59+):** **Unified `eboot.bin`** (OpenOrbis standard, full UI in one FSELF). Kernel loader dynlinks PLT — no split **`guest.oelf`**, no **`guestPlainLoaderRun`** (**CE-34878-0**). See **`docs/PS4-HOMEBREW-LOADER-PATTERNS.md`**. **Delete tile** before install if switching from an old split-chain build.

**CE-41839-5:** Usually invalid SELF/PKG — not eboot size (Apollo ~6.5 MiB eboot works on the same console).

## IDs (pre-release 0.7)

| | |
| --- | --- |
| TITLE_ID | `CSTP00003` |
| CONTENT_ID | `IV0000-CSTP00003_00-PS4LINUXL0700001` |
| Legacy (remove from Library) | `CSTP00002`, `CSTP00001` |
