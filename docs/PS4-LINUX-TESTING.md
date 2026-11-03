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
| **Unit** | `swift test` in `tools/PS4LinuxTools` — PKG versioning, param.sfo parsing, language paths, constants |
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
| BootTrace / eboot chain | Constants | Source + Makefile | Log lines `eboot:` / `guest:` |
| `LinuxBootConfig` JSON | — | — | Manual / future host JSON tests |
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
