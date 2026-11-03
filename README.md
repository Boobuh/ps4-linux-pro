# PS4 Linux Pro

Homebrew **Library** app for GoldHEN (FW 11.00+): install a standalone **PS4 Linux** PKG, sync internal boot files from your Mac, and launch kexec Linux from **`/data/linux/boot/`** (Baikal Pro / internal HDD).

| | |
| --- | --- |
| **TITLE_ID** | `CSTP00002` |
| **CONTENT_ID** | `IV0000-CSTP00002_00-PS4LINUXL0700000` |

## Quick start (Mac)

```bash
brew install llvm   # Apple Silicon: /opt/homebrew/opt/llvm/bin/clang
swift tools/ps4-linux-launcher-build.swift
swift tools/ps4-linux-sync.swift sync
```

Install **`ps4-linux-launcher-app/linux-loader/PS4-Linux-v*.pkg`** on the console via GoldHEN Package Installer → **`/data/pkg/`**.

## Docs

| Doc | Topic |
| --- | --- |
| [docs/PS4-LINUX-LOADER-PKG.md](docs/PS4-LINUX-LOADER-PKG.md) | PKG install, updates, logging |
| [docs/PS4-LINUX-TESTING.md](docs/PS4-LINUX-TESTING.md) | Unit / integration / FTP e2e tests |
| [docs/PS4-LINUX-XMB-LAUNCH.md](docs/PS4-LINUX-XMB-LAUNCH.md) | Library launch flow |
| [docs/PS4-LINUX-PAYLOAD-LAUNCH.md](docs/PS4-LINUX-PAYLOAD-LAUNCH.md) | Payload / PayLoader fallback |
| [docs/PS4-LINUX-AUTO.md](docs/PS4-LINUX-AUTO.md) | Initramfs / auto-install notes |

## Tests

```bash
swift tools/ps4-linux-test.swift
```

## License

GPL-3.0 — see [LICENSE](LICENSE). Incorporates GPLv3 lineage from community PS4 homebrew loader UI patterns; see file headers in `ps4-linux-launcher-app/linux-loader/`.

## Contributors

See [CONTRIBUTORS.md](CONTRIBUTORS.md).
