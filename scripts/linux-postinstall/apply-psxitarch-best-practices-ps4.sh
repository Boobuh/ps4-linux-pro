#!/bin/bash
# Hippie68/psxitarch best practices for PS4 Arch — stable pacman, JWM Ubuntu chrome, health checks.
# Run as root on a booted psxitarch (SSH). Does not replace a broken Arch.img (see docs/PS4-ARCHIMG-FSCK.md).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo -i)" >&2; exit 1; }

SCRIPT_DIR="${PS4_SCRIPT_DIR:-}"
if [[ -z "$SCRIPT_DIR" ]]; then
  _self="${BASH_SOURCE[0]:-$0}"
  SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)" 2>/dev/null || SCRIPT_DIR=/tmp
fi
export PS4_SCRIPT_DIR="$SCRIPT_DIR"
DESKTOP_USER="${DESKTOP_USER:-psxita}"

echo "=== apply-psxitarch-best-practices-ps4 $(date) ==="

# Stop half-finished XFCE/LightDM installers that wedge pacman on corrupt FS.
systemctl disable ps4-ubuntu-gui-install.service 2>/dev/null || true
systemctl stop ps4-ubuntu-gui-install.service 2>/dev/null || true
rm -f /var/lib/ps4-ubuntu-gui-installed /var/lib/pacman/db.lck 2>/dev/null || true
pkill -9 pacman gpg 2>/dev/null || true

# --- Pacman: archives mirrors, no surprise gpg hang, no full -Syu on live session ---
if [[ -f /etc/pacman.conf ]] && ! grep -q '^SigLevel = Never' /etc/pacman.conf 2>/dev/null; then
  cp -a /etc/pacman.conf "/etc/pacman.conf.bak-best-$(date +%Y%m%d)" 2>/dev/null || true
  sed -i 's/^SigLevel.*/SigLevel = Never\nLocalFileSigLevel = Never/' /etc/pacman.conf
fi
if [[ ! -s /etc/pacman.d/mirrorlist.ps4-bak ]]; then
  cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.ps4-bak 2>/dev/null || true
  cat >/etc/pacman.d/mirrorlist <<'MIR'
Server = https://archive.archlinux.org/repos/2021/09/07/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
MIR
fi
pacman -Sy --noconfirm 2>/dev/null || true

# Pin libpng for JWM; drop feh (glibc skew on old rootfs).
if [[ -f /tmp/libpng-1.6.37-3-x86_64.pkg.tar.zst ]]; then
  pacman -U --noconfirm /tmp/libpng-1.6.37-3-x86_64.pkg.tar.zst 2>/dev/null || true
fi
pacman -Rdd --noconfirm feh 2>/dev/null || true

# --- Storage health (informational; offline fsck still required if I/O errors) ---
if [[ -x "$SCRIPT_DIR/fsck-archimg-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/fsck-archimg-ps4.sh" || true
fi
ROOT_DEV="$(awk '$2=="/"{print $1; exit}' /proc/mounts)"
if command -v e2fsck >/dev/null 2>&1 && [[ -n "$ROOT_DEV" ]]; then
  if e2fsck -n -f "$ROOT_DEV" 2>&1 | grep -qiE 'error|input/output'; then
    echo "WARN: Arch.img reports filesystem errors — plan Mac offline fsck (docs/PS4-ARCHIMG-FSCK.md) or reinstall."
  fi
fi

# --- Home perms + Ubuntu JWM (PS4-safe desktop path) ---
if [[ -x "$SCRIPT_DIR/fix-psxita-permissions-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/fix-psxita-permissions-ps4.sh" || true
fi
if [[ -x "$SCRIPT_DIR/ubuntu-jwm-look-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/ubuntu-jwm-look-ps4.sh"
fi

# --- PSXITA conveniences ---
if [[ -x "$SCRIPT_DIR/display-stay-on-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/display-stay-on-ps4.sh" "$DESKTOP_USER" 2>/dev/null || true
fi
if [[ -x /usr/local/sbin/enable-bluetooth-ps4.sh ]]; then
  /usr/local/sbin/enable-bluetooth-ps4.sh "$DESKTOP_USER" 2>/dev/null || true
elif [[ -x "$SCRIPT_DIR/enable-bluetooth-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/enable-bluetooth-ps4.sh" "$DESKTOP_USER" 2>/dev/null || true
fi

# Light GTK theme refresh without -Syu (ubuntu-look-arch subsets).
if [[ -x "$SCRIPT_DIR/ubuntu-look-arch.sh" ]]; then
  PS4_SKIP_SYU=1 bash "$SCRIPT_DIR/ubuntu-look-arch.sh" 2>/dev/null || true
fi

# Optional XFCE polish only when xfwm4 runs (skip on bus-error installs).
if command -v xfwm4 >/dev/null 2>&1 && runuser -u "$DESKTOP_USER" -- xfwm4 --version >/dev/null 2>&1; then
  echo "xfwm4 OK — you may run: bash $SCRIPT_DIR/ubuntu-xfce-polish-ps4.sh"
else
  echo "skip XFCE polish: xfwm4 unavailable (use JWM until Arch.img is healthy)."
fi

cat <<'EOF'

=== Done ===
Desktop: JWM + Ubuntu colors (Activities menu, purple wallpaper, dark panel).
HDMI black: ALT+F11 / ALT+F12 (psxitarch), or SSH: recover-black-screen-ps4.sh
Mac remote: docs/PS4-LINUX-REMOTE-CONTROL.md
If pacman/I/O errors persist: offline fsck Arch.img or fresh psxitarch (hippie68 initramfs + aligned install).

EOF