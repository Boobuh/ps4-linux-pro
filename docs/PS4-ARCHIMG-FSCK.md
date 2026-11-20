# Repair corrupted `Arch.img` (psxitarch)

When Linux shows **JWM only**, **black XFCE**, **bus error** on `openbox`/`xfwm4`, or `e2fsck` reports **Input/output error** on `/dev/loop0`, the ext2 root inside **`/ps4hdd/home/Arch.img`** is damaged. Theme/panel scripts cannot fix that while the image is mounted.

## Option A — fsck on your Mac (keeps the install)

1. On PS4 Linux, ensure SSH works; on Orbis, FTP user `psxita` can reach **`/user/home/Arch.img`** (same file as `/ps4hdd/home/Arch.img`).
2. Copy `Arch.img` to the Mac (full multi‑GB file; do not interrupt).
3. On macOS:

```bash
brew install e2fsprogs   # if needed
img="$HOME/Desktop/Arch.img"
hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$img"   # or: losetup on Linux
# Note the loop/raw device, then:
sudo e2fsck -f -y /dev/rdiskN    # use the attached whole-disk node from hdiutil/loop
```

4. Upload the repaired `Arch.img` back via FTP (power off Linux cleanly first if possible).
5. Boot **installed Linux** again; re-run `scripts/linux-postinstall/restore-xfce-light-ps4.sh` as root.

## Option B — fsck from SSH without X (same console)

Autologin runs `startx` on tty1 only when **not** SSH. You cannot offline-fsck `/` from a normal SSH session while it is mounted.

## Option C — fresh install

From the PS4 loader app, use **`--wipe-arch`** (or wipe partial image) and reinstall psxitarch. Back up anything you need from FTP first.

## After repair

```bash
# root on console
bash /path/to/restore-xfce-light-ps4.sh
bash /path/to/ubuntu-xfce-polish-ps4.sh
```

`restore-xfce-light-ps4.sh` uses **Openbox + XFCE panel** when `xfwm4` is broken but GTK is healthy again.