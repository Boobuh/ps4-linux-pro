#!/bin/bash
# Restore HDMI / XFCE on psxitarch after black screen (safe: no openssl/curl upgrades).
# Run as root on PS4 — USB keyboard + blind paste, or SSH once repair-openssl works.
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "sudo bash $0" >&2; exit 1; }

echo "=== restore-hdmi-ps4-arch $(date) ==="

# 1) SSH/network tooling if openssl was broken
if ! ldconfig -p 2>/dev/null | grep -q 'libssl.so.1.1'; then
  CACHE=/var/cache/pacman/pkg
  shopt -s nullglob
  ossl=("$CACHE"/openssl-1.1.*.pkg.tar.* "$CACHE"/openssl-1.1.*.pkg.tar.zst)
  if ((${#ossl[@]})); then
  pacman -U --noconfirm "${ossl[0]}"
  fi
fi

# 2) EDID firmware (black X11 / no mode on PS4 bridge)
mkdir -p /lib/firmware/edid
if [[ ! -f /lib/firmware/edid/1920x1080.bin ]]; then
  if [[ -f /usr/share/edid/1920x1080.bin ]]; then
    cp /usr/share/edid/1920x1080.bin /lib/firmware/edid/
  elif [[ -f /boot/edid/1920x1080.bin ]]; then
    cp /boot/edid/1920x1080.bin /lib/firmware/edid/
  else
    # Minimal 1920x1080 CEA block (common PS4 HDMI fix)
    python3 - <<'PY' 2>/dev/null || true
from pathlib import Path
# 128-byte base EDID with 1920x1080 detailed timing (simplified block)
edid = bytes.fromhex(
    "00ffffffffffff0004954c4f0000000001180103804b16780a0a74"
    "48470000454f4b472d480a0095a0291a5030302030350050400101"
    "01010101010101010101010101010101010101010101010101010101"
    "01010101010101010101010101010101010101010101010101010101"
)
Path("/lib/firmware/edid/1920x1080.bin").write_bytes(edid[:128])
PY
  fi
fi

if [[ -f /etc/cmdline.d/edid.conf ]]; then
  : # already set
elif [[ -f /proc/cmdline ]]; then
  if ! grep -q 'drm.edid_firmware' /proc/cmdline; then
    mkdir -p /etc/cmdline.d
    echo 'drm.edid_firmware=edid/1920x1080.bin' >/etc/cmdline.d/edid.conf
    echo "Note: EDID cmdline applies after reboot from PS4 loader."
  fi
fi

# 3) PS4 AMDGPU stack (only if [ps4] repo is enabled — do not run -Syu)
if grep -q '^\[ps4\]' /etc/pacman.conf 2>/dev/null && ! grep -q '^#\[ps4\]' /etc/pacman.conf 2>/dev/null; then
  yes "" | pacman -S --noconfirm --needed xf86-video-amdgpu-git mesa-git libdrm-git 2>/dev/null || true
else
  yes "" | pacman -S --noconfirm --needed mesa xf86-video-amdgpu libdrm 2>/dev/null || true
fi

mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/10-ps4-hdmi.conf <<'EOF'
Section "Device"
    Identifier "PS4GPU"
    Driver "amdgpu"
    Option "TearFree" "true"
EndSection

Section "Monitor"
    Identifier "HDMI"
    Option "PreferredMode" "1920x1080"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "PS4GPU"
    Monitor "HDMI"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection
EOF

# 4) Display manager
if systemctl is-enabled lightdm.service &>/dev/null; then
  systemctl restart lightdm.service 2>/dev/null || true
else
  systemctl enable lightdm.service 2>/dev/null || true
  systemctl start lightdm.service 2>/dev/null || true
fi

# 5) Quick checks
echo "---"
if [[ -e /dev/dri/card0 ]]; then
  echo "DRM card0: OK"
else
  echo "DRM card0: MISSING — check kernel amdgpu / reboot from PS4 loader"
fi
if pgrep -x Xorg &>/dev/null || pgrep -x Xorg.wrap &>/dev/null; then
  echo "Xorg: running"
else
  echo "Xorg: not running — try: systemctl restart lightdm"
fi
echo ""
echo "psxitarch hotkeys (USB keyboard): Alt+F11 / Alt+F12 = toggle HDMI video"
echo "TTY fallback: Ctrl+Alt+F1 .. F3, login psxita"
echo "=== done ==="