# Remote control PS4 Linux from Mac

Two modes:

| Mode | When | Tool |
|------|------|------|
| **GoldHEN FTP** | PS4 OS, port 2121 | `ps4-linux-console-cycle`, `ps4-linux-sync` |
| **SSH** | Arch Linux desktop, port 22 | `ps4-linux-remote` |

Arch has **no** GoldHEN FTP. Full control from the Mac means **SSH keys**, not passwords.

**Image login (hippie68 psxitarch):** desktop user **`psxita`** / **`changeit`** (for `sudo` in a local terminal). That password works for `ssh psxita@10.0.1.7`, but **`root` SSH password is normally disabled** — use the one-time bootstrap below for passwordless `root@` from the Mac.

## One-time bootstrap (5 minutes)

```bash
cd /Users/Shared/dev/ps4-linux-pro
swift tools/ps4-linux-remote.swift setup
```

Terminal A:

```bash
swift tools/ps4-linux-remote.swift serve
```

On **PS4 Linux** (Terminal):

```bash
curl -fsSL "http://10.0.1.13:8766/enable-mac-control.sh" | sudo bash -s -- "http://10.0.1.13:8766/ps4-linux.pub"
```

(Use your Mac IP from `setup` output — often `10.0.1.13`.)

Terminal B (Mac):

```bash
swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- uname -a
swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- pacman -Syu
```

Key file: `~/.ssh/ps4_linux_ed25519`

## Daily commands

```bash
swift tools/ps4-linux-remote.swift probe --host 10.0.1.7
swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- systemctl status sshd
swift tools/ps4-linux-remote.swift push --host 10.0.1.7 ./foo.txt /tmp/foo.txt
swift tools/ps4-linux-remote.swift pull --host 10.0.1.7 /etc/hostname ./hostname
swift tools/ps4-linux-remote.swift screenshot --host 10.0.1.7 tmp/ps4-hdmi-screenshot.png
```

`screenshot` grabs `/dev/fb0` on the console (what HDMI is driving), pulls the raw buffer, and writes a PNG on the Mac (`tools/ps4-linux-fb-to-png.py`). Use this to verify desktop changes without guessing. Pure black usually means a black HDMI output or DRI bypassing the framebuffer—not necessarily a failed capture.

## On PS4 OS (optional)

Upload pubkey + bootstrap script while GoldHEN FTP is up (before booting Linux):

```bash
swift tools/ps4-linux-remote.swift upload-bootstrap --host 10.0.1.7
```

Files land on `/data/linux/boot/` for reference.

## Ubuntu look (after SSH works)

```bash
swift tools/ps4-linux-remote.swift push --host 10.0.1.7 \
  scripts/linux-postinstall/ubuntu-look-arch.sh /tmp/ubuntu-look-arch.sh
swift tools/ps4-linux-remote.swift exec --host 10.0.1.7 -- bash /tmp/ubuntu-look-arch.sh
```

Or pipe via serve + `exec` curl from Linux — see `PS4-LINUX-UBUNTU-DESKTOP-LOOK.md`.