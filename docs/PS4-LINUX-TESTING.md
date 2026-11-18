# PS4 Linux — testing

We cannot run **100% line coverage** on the on-console OpenOrbis app (Orbis video, pad, `LoadExec`, GoldHEN) on macOS without a PS4 simulator. What we **can** cover completely is documented below.

## Run everything (Mac)

```bash
cd /path/to/ps4-linux-pro
swift tools/ps4-linux-test.swift
```

Stages:

| Stage | What it covers |
| --- | --- |
| **Unit** | `swift test` in `tools/PS4LinuxTools` — PKG versioning, param.sfo parsing, language paths, **Linux install detect / boot config / menu / kexec `.bin` rules** |
| **Integration** | Repo layout (BootTrace, Makefile, assets), **built** `PS4-Linux-v*.pkg` param.sfo vs `PKG_BUILD_NUM` |
| **E2E** | Optional FTP smoke to PS4 (`PS4_HOST` / `PS4_PORT`, default `10.0.1.7:2121`) — pkg on `/data/pkg/`, boot log paths |

Skip E2E automatically if FTP is down (CI-friendly).

## Unit tests only

```bash
swift test --package-path tools/PS4LinuxTools
```

## Coverage map (honest)

| Area | Unit | Integration | E2E (PS4) |
| --- | --- | --- | --- |
| PKG `APP_VER` / `VERSION` / filenames | 100% (`PkgVersioning`) | Built PKG + PkgTool | Install + Package Installer |
| Language `X21.json` path | 100% | Asset dir on disk | — |
| param.sfo rules | 100% (`PkgInspector`) | Latest `.pkg` | Installed `app.pkg` |
| **eboot.bin** / **CE-41839-5** | **`FselfShipGate`** + `FselfHardwareReferenceTests`: real Apollo/OneFamily FTP eboots, real `create-fself-macos` / `ps4-linux-make-fself.py` / `ps4-linux-fself.sh` on `build/eboot.elf`; authinfo layout offset; create-fself size floor; `.ps4-linux-fself-method` stamp | `validateBuildTree` on built loader | Empty log + blue screen (kernel reject — not fully simulatable on Mac) |
| **E2E launch** | **`ConsoleLaunchE2E`** — if FTP up and console **installed PKG = Mac latest**, **empty logs fail** (`PS4_LINUX_E2E_STRICT=0` to skip) | — | `RUN START` on hardware |
| `LinuxBootConfig` (clamp, normalize, lite JSON) | **`LinuxBootConfigLogic`** (+ C++ header parity) | — | Save/write on console |
| HDD install detect / wipe / menu actions | **`LinuxInstallDetectLogic`**, **`LinuxMenuLogic`** | Overlay scripts in repo | Arch.img + boot on hardware |
| Kexec vs ELF payload pick | **`KexecLoaderBinLogic`** (+ real `linux-1024mb.bin` if present) | sync payloads | GoldHEN socket |
| Graphics / pad / UI loop | — | — | Manual launch on hardware |

**Target:** 100% of **Mac-testable** logic in `PS4LinuxCore`; integration guards release artifacts; E2E confirms deploy + logs when the console is online.

## CI suggestion (GitLab)

```yaml
ps4-linux-test:
  script:
    - swift test --package-path tools/PS4LinuxTools
    - swift tools/ps4-linux-test.swift
  rules:
    - changes:
        - ps4-linux-launcher-app/**/*
        - tools/**/*
```

Add a scheduled job with `PS4_HOST` for nightly E2E when the console is reachable.

## Keeping build and tests in sync

Version math lives in **`tools/PS4LinuxTools/Sources/PS4LinuxCore/PkgVersioning.swift`**. When changing bump rules, update that module and run `swift tools/ps4-linux-test.swift` before shipping a PKG.
