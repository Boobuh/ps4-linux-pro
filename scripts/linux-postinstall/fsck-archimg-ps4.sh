#!/bin/bash
# Repair Arch.img (loop0) when e2fsck on disk is readable. Root only; REQUIRES unmounted / or live boot.
# On a running psxitarch root, this only schedules check + reinstalls e2fsprogs if possible.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

echo "=== fsck-archimg-ps4 $(date) ==="
ROOT_DEV="$(awk '$2=="/"{print $1; exit}' /proc/mounts)"
[[ -n "$ROOT_DEV" ]] || { echo "no root device" >&2; exit 1; }
echo "root device: $ROOT_DEV"

if [[ -f /var/cache/pacman/pkg/e2fsprogs-*.pkg.tar.* ]]; then
  pkg=(/var/cache/pacman/pkg/e2fsprogs-*.pkg.tar.*)
  pacman -U --noconfirm "${pkg[0]}" 2>/dev/null || true
elif [[ -f /tmp/e2fsprogs.pkg.tar.zst ]]; then
  pacman -U --noconfirm /tmp/e2fsprogs.pkg.tar.zst 2>/dev/null || true
fi

if command -v e2fsck >/dev/null; then
  echo "Attempting read-only check (may fail if / is mounted)..."
  e2fsck -n -f "$ROOT_DEV" 2>&1 || true
else
  echo "e2fsck missing or unreadable — copy e2fsprogs pkg to /tmp and pacman -U, or reinstall Arch.img"
fi

# Force full fsck after next clean shutdown from Linux (ext2/ext3/ext4)
if command -v tune2fs >/dev/null 2>&1; then
  tune2fs -C 999999 "$ROOT_DEV" 2>/dev/null || true
fi

mkdir -p /etc/systemd/system
cat >/etc/systemd/system/ps4-fsck-root.service <<EOF
[Unit]
Description=PS4 Arch.img fsck before graphical session
DefaultDependencies=no
Before=getty@tty1.service
ConditionPathExists=/run/ps4-fsck-pending

[Service]
Type=oneshot
ExecStart=/usr/sbin/e2fsck -f -y $ROOT_DEV
ExecStartPost=/bin/rm -f /run/ps4-fsck-pending
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

touch /run/ps4-fsck-pending 2>/dev/null || true
systemctl enable ps4-fsck-root.service 2>/dev/null || true

echo "If fsck cannot fix while running: reboot Linux from PS4 loader, SSH in BEFORE startx, run:"
echo "  systemctl isolate rescue.target && e2fsck -f -y $ROOT_DEV && reboot"
echo "Worst case: backup /ps4hdd/home/Arch.img from XMB FTP, --wipe-arch reinstall from PS4 app."