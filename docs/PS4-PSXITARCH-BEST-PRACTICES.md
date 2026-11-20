# psxitarch best practices (this project)

Aligned with **hippie68** install hygiene, **PSXITA v3** conveniences, and what survives on **1 GB VRAM** PS4 Linux.

## Default desktop policy

| Priority | Path | When |
|----------|------|------|
| 1 | **JWM + Ubuntu chrome** (`ubuntu-jwm-look-ps4.sh`) | Corrupt or fragile `Arch.img`, `xfwm4` bus errors |
| 2 | **XFCE + Yaru-ish themes** (`ubuntu-xfce-polish-ps4.sh`) | After **offline fsck** or clean reinstall |
| 3 | **Pre-built images** | Worst case: [7coil/archlinux-on-ps4](https://github.com/7coil/archlinux-on-ps4) Actions artifact or [Erkkola XFCE](https://github.com/ErkkolaMaitohappo/ps4-arch-distros/releases) |

## One command on the console

```bash
sudo bash /tmp/apply-psxitarch-best-practices-ps4.sh
```

From Mac (pushes postinstall bundle + assets):

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-remote.swift push --host 10.0.1.7 \
  scripts/linux-postinstall/apply-psxitarch-best-practices-ps4.sh /tmp/
# Also push the whole postinstall dir (see apply script sibling scripts).
swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- \
  bash /tmp/apply-psxitarch-best-practices-ps4.sh
```

Or HTTP serve:

```bash
tools/ps4-linux-serve-scripts.sh
# On PS4: curl -fsSL "http://<mac>:8766/apply-psxitarch-best-practices-ps4.sh" | sudo bash
```

## What the apply script does

1. Stops **stuck ubuntu-gui-install** / pacman locks.
2. **Archive mirrors** + **SigLevel Never** (avoids keyserver hangs on bad I/O).
3. **Skips full `-Syu`**; pins **libpng 1.6.37** if pkg present; removes **feh**.
4. Runs **fsck-archimg** health + warns on `e2fsck` errors.
5. **fix-psxita-permissions** + **ubuntu-jwm-look** (full getty restart).
6. **display-stay-on**, **bluetooth** menu if installed.
7. **ubuntu-look-arch** with `PS4_SKIP_SYU=1` (fonts/icons only).

## Boot / reinstall (community)

| Piece | Use |
|-------|-----|
| [hippie68 initramfs](https://github.com/hippie68/psxitarch-how-to/releases) | Partition **alignment** at install |
| [ps4-linux-loader](https://github.com/ps4-linux/ps4-linux-loader) | VRAM via `vram.txt`; `linux-1024mb.elf` for desktop |
| [Hakkuraifu docs](https://github.com/Hakkuraifu/PS4Linux-Documentation) | Kernel + rescue commands |
| PS4 loader app **`--wipe-arch`** | Fresh `Arch.img` when fsck cannot recover |

## Roll back to stock psxitarch UI

`rollback-psxitarch-ui-defaults-ps4.sh` undoes **PS4-Linux-Pro** Ubuntu/JWM tweaks: Gtk overrides, custom `jwmrc`, `jwm -f` in `.xinitrc`. It restores **`~/.ps4-linux-pro-ui-backup`** when that exists (saved on the **first** `ubuntu-jwm-look-ps4.sh`), otherwise copies **`/etc/system.jwmrc`**. Restarts `getty@tty1`.

```bash
sudo bash /tmp/rollback-psxitarch-ui-defaults-ps4.sh
```

## After `Arch.img` is healthy

```bash
bash /path/to/ubuntu-xfce-polish-ps4.sh
# stock JWM UI: bash rollback-psxitarch-ui-defaults-ps4.sh
```

See also: [PS4-ARCHIMG-FSCK.md](PS4-ARCHIMG-FSCK.md), [PS4-LINUX-REMOTE-CONTROL.md](PS4-LINUX-REMOTE-CONTROL.md).