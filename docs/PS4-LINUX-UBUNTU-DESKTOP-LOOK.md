# Ubuntu-style desktop on Arch (psxitarch)

Your install is **Arch** (`arch.tar.xz` / hippie68 psxitarch), not Ubuntu. You **cannot** swap to Ubuntu rootfs without reinstalling a different distro archive. You **can** get very close visually.

## Recommended (PS4 hardware)

| Approach | Look | Cost on PS4 |
|----------|------|-------------|
| **Yaru theme + Ubuntu font + Papirus** on existing **XFCE/MATE** | Ubuntu 22.04-ish | Low (packages + logout) |
| **GNOME Shell** full session | Real Ubuntu layout | High RAM/CPU — often sluggish on PS4 |

Use the **theme path** first.

## One-shot script (from Linux)

On the PS4 desktop, open a terminal:

### Copy from Mac without SSH or FTP

**Arch has no GoldHEN FTP.** Use HTTP from your Mac on the same Wi‑Fi:

**Mac** (leave running):

```bash
cd /Users/Shared/dev/ps4-linux-pro
tools/ps4-linux-serve-scripts.sh
```

**PS4 Linux terminal** (replace `<mac-ip>` with the IP printed, e.g. `10.0.1.13`):

```bash
curl -fsSL "http://<mac-ip>:8766/ubuntu-look-arch.sh" | sudo bash
```

Then **log out and back in**.

Optional: reboot to PS4 OS, FTP-upload the script to `/data/linux/boot/ubuntu-look-arch.sh` over GoldHEN; after next Linux boot, if that path is mounted, run `sudo bash /data/linux/boot/ubuntu-look-arch.sh`.

## Manual (pacman)

```bash
sudo pacman -Syu
sudo pacman -S --needed gnome-themes-extra gtk-engine-murrine papirus-icon-theme ttf-ubuntu-font-family
# If available in your mirrors:
sudo pacman -S yaru-gtk-theme yaru-icon-theme
```

**XFCE:** Settings → Appearance → Style **Yaru-dark** (or Adwaita-dark), Icons **Yaru** or **Papirus**.

## Full GNOME (optional, heavy)

```bash
sudo pacman -S gnome gnome-extra
# enable display manager — only if you have enough VRAM and accept slow UI
sudo systemctl enable gdm
```

Not recommended on **1 GB VRAM** Linux unless you moved loader VRAM up and accept performance hits.

## PS4 launcher app

The **Library** app UI (`CSTP00003`) is separate from Linux desktop theming — it stays the blue PS4 Linux menu unless we redesign that eboot.

## Related

- Install path: `docs/PS4-LINUX-BAIKAL-ASSETS.md`
- SSH from Mac when Linux is on Wi‑Fi: user **`psxita`**, password **`changeit`** ([hippie68 psxitarch](https://github.com/hippie68/psxitarch-how-to)). Desktop auto‑logs in as `psxita`; use `sudo` for root. **`root` over SSH** usually needs a key (OpenSSH default `prohibit-password`), not the same password prompt — run `enable-mac-control.sh` once, then `ssh -i ~/.ssh/ps4_linux_ed25519 root@10.0.1.7`.