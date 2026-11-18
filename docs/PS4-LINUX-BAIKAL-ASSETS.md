# Baikal internal Linux — assets and payloads

**Goal:** Install and run Linux on **Baikal (Pro/Slim)** from the **internal HDD** without a USB stick during boot.

## Mac one-time / refresh

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-sync.swift sync --install-gb 100
```

If only loader files were wrong (ELF disguised as `.bin`):

```bash
swift tools/ps4-linux-sync.swift payloads
```

See **`downloads/ps4-linux-baikal/README.md`** for file layout.

## Console paths (after sync)

| Path | Purpose |
|------|---------|
| `/data/linux/boot/bzImage` | Kernel |
| `/data/linux/boot/initramfs.cpio.gz` | Nazky + `install-HDD.sh` |
| `/data/linux/boot/vram.txt` | `1024` for first boot |
| `/user/system/boot/arch.tar.xz` | Distro archive (internal install) |
| `/user/system/boot/ps4-install-gb.txt` | Fallback install size from sync (app default **100 GB**, min **50**) |
| `/data/payloads/linux-1024mb.bin` | **Kexec loader** for GoldHEN socket (329088 B) |
| `/data/payloads/linux-1024mb.elf` | PayLoader LaunchPad alternative |

## PS4 Linux app (Library)

1. Install latest **`PS4-Linux-v*.pkg`** from `/data/pkg/`.
2. **Install detect** — reads **`/user/home/Arch.img`**, **`install-status.txt`**, and **`ps4-linux-installed.meta`** (written at end of install). Shows **Boot installed Linux** vs **Install on HDD**.
3. **Install partition size** — presets **50–200 GB** or **Custom** (Left/Right ±10 GB). Default **100 GB**, minimum **50 GB**. Saved to `ps4-install-gb.txt` before kexec.
4. **Linux RAM (VRAM)** — **512 / 1024 / 2048 / 4096 MB** (Baikal Pro usually **1024**).
5. **Setup new install** — confirms wipe of **Arch.img** then kexec (full reinstall).
6. **Input:** TV **D-pad** on CEC remote handle; **Options** = Triangle **`0x1000`** (ignored). **Do not** use `scePadReadStateExt` / pad privilege hacks — **CE-34878-0** on GoldHEN. Fallback confirm: **hold Down ~1s**. DualShock **Cross** confirms.

The app sends the loader via **GoldHEN port 9090/9021**, not in-process ELF (avoids CE-34878 when opening the system menu).

## Verify payloads

Kexec `.bin` must **not** begin with ELF magic. From Mac:

```bash
curl -s ftp://10.0.1.7:2121/data/payloads/linux-1024mb.bin | xxd -l 4
# Expect e9… or similar — NOT 7f45 4c46
```

## Related

- **`docs/PS4-LINUX-PAYLOAD-LAUNCH.md`** — PayLoader, VRAM, GoldHEN version
- **`docs/PS4-LINUX-LOADER-PKG.md`** — PKG install and updates
