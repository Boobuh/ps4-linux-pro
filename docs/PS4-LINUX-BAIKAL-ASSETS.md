# Baikal internal Linux — assets and payloads

**Goal:** Install and run Linux on **Baikal (Pro/Slim)** from the **internal HDD** without a USB stick during boot.

## Mac one-time / refresh

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-sync.swift sync --install-gb 100
```

**Install netdebug (HTTP log during HDD install):** GoldHEN FTP is **off** after kexec. Enable BusyBox `httpd` on **:8765** serving `install-status.txt`:

```bash
swift tools/ps4-linux-sync.swift sync --host 10.0.1.7 --netdebug   # or PS4LINUX_INSTALL_NETDEBUG=1
# During install (Library → Install on HDD):
swift tools/ps4-linux-console-cycle.swift install-watch --host 10.0.1.7
```

**Network:** Before kexec the app writes **`/user/system/boot/ps4-net-inherit.conf`** (and `/data/linux/boot/`) with Orbis **Wi‑Fi or LAN IP, mask, gw, iface**. Install initramfs applies that for netdebug HTTP — no manual `10.0.1.7` file. Enable: `etc/ps4-linux-install-netdebug` in initramfs + `ps4-install-netdebug.enable` on HDD (`sync --netdebug`).

**Fail-safe:** `sync` / `prepare` / `upload` run **`ps4-linux-install-guard`** — refuses to ship an initramfs whose `install-HDD.sh` uses the broken `switch_root /newroot /newroot/sbin/init` pattern, skips tar-without-checks, or lacks revision stamp **`etc/ps4-linux-install-hdd.rev` (rev 3)**. On-console pivot uses **`fail_safe_switch_root`** → **`/sbin/init`** only.

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
2. **Install detect** — reads **`/user/home/Arch.img`**, **`install-status.txt`**, and **`ps4-linux-installed.meta`** (under `/user/system/boot/` or `/data/linux/boot/`). When ready, primary action is **Boot installed Linux** and writes **`ps4-linux-launch-intent.txt`** = `boot` before kexec (initramfs mounts existing Arch.img; no reinstall).
3. **Install partition size** — presets **50–200 GB** or **Custom** (Left/Right ±10 GB). Default **100 GB**, minimum **50 GB**. Saved to `ps4-install-gb.txt` before kexec.
4. **Linux RAM (VRAM)** — **512 / 1024 / 2048 / 4096 MB** (Baikal Pro usually **1024**).
5. **Setup new install** — confirms wipe of **Arch.img** then kexec (full reinstall).
6. **Input:** TV **D-pad** on CEC remote handle; **Options** = Triangle **`0x1000`** (ignored). **Do not** use `scePadReadStateExt` / pad privilege hacks — **CE-34878-0** on GoldHEN. Fallback confirm: **hold Down ~1s**. DualShock **Cross** confirms.
7. **Download kernel** — menu downloads **bzImage** over HTTPS to **`/data/linux/boot/bzImage`** (catalog in `KernelCatalog.cpp`). **initramfs** still comes from Mac **`ps4-linux-sync`** (custom install overlay).
8. **Boot stack check** — before kexec, app verifies **`bzImage`** (≥ 8 MB, catalog size range) and **`initramfs.cpio.gz`** (≥ 3 MB) under **`/data/linux/boot/`**. Mac: **`swift tools/ps4-linux-console-cycle.swift status`** prints the same sizes over FTP.

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
