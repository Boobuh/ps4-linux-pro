#!/bin/bash
# PS4 psxitarch: upgrade JWM → XFCE + LightDM + Ubuntu (Yaru) look. Run as root.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root only" >&2; exit 1; }

echo "=== ubuntu-gui-ps4: start $(date) ==="

# PS4 Wi‑Fi: broken IPv6 breaks pacman mirror fetch; stale community repo 404s.
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
if grep -q '^\[community\]' /etc/pacman.conf 2>/dev/null; then
  sed -i '/^\[community\]/,/^\[multilib\]/{ /^Include/ s/^/#/; /^\[community\]/ s/^/#/ }' /etc/pacman.conf
fi
if grep -q '^\[ps4\]' /etc/pacman.conf 2>/dev/null; then
  sed -i '/^\[ps4\]/,/^$/ s/^/#/' /etc/pacman.conf
fi
rm -f /var/lib/pacman/db.lck

if ! pacman-key -l 2>/dev/null | grep -q 'Frederik Schwan'; then
  cp -a /etc/pacman.conf /etc/pacman.conf.keybootstrap
  sed -i 's/^SigLevel.*/SigLevel = Never\nLocalFileSigLevel = Never/' /etc/pacman.conf
  pacman -Sy --noconfirm
  yes | pacman -S --noconfirm archlinux-keyring
  pacman-key --init
  pacman-key --populate archlinux 2>/dev/null || true
  mv -f /etc/pacman.conf.keybootstrap /etc/pacman.conf
  pacman -Sy --noconfirm
fi

# Old psxitarch ships libfm-gtk2/pcmanfm; XFCE pulls libfm-gtk3.
pacman -Rdd --noconfirm pcmanfm libfm-gtk2 2>/dev/null || true
# Skip full -Syu. Drop pinned 2021 gstreamer stack so Thunar/XFCE deps can resolve.
for legacy in gst-plugins-base gst-plugins-good gst-libav parole; do
  pacman -Rdd --noconfirm "$legacy" 2>/dev/null || true
done

XFCE_PKGS=(
  xfce4-session xfwm4 xfdesktop thunar xfce4-panel xfce4-settings xfce4-terminal
  xfconf libxfce4ui libxfce4util exo garcon
  lightdm lightdm-gtk-greeter
  network-manager-applet polkit-gnome
  gtk-layer-shell elementary-icon-theme
)
yes "" | pacman -S --noconfirm --needed "${XFCE_PKGS[@]}"

LIGHTDM=/etc/lightdm/lightdm.conf
if [[ -f "$LIGHTDM" ]] && ! grep -q '^autologin-user=psxita' "$LIGHTDM"; then
  sed -i 's/^#autologin-user=.*/autologin-user=psxita/' "$LIGHTDM" 2>/dev/null || true
  sed -i 's/^#autologin-session=.*/autologin-session=xfce/' "$LIGHTDM" 2>/dev/null || true
  if ! grep -q '^autologin-user=' "$LIGHTDM"; then
    printf '\n[Seat:*]\nautologin-user=psxita\nautologin-session=xfce\n' >>"$LIGHTDM"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/ubuntu-look-arch.sh" ]]; then
  bash "$SCRIPT_DIR/ubuntu-look-arch.sh"
elif [[ -f /tmp/ubuntu-look-arch.sh ]]; then
  bash /tmp/ubuntu-look-arch.sh
fi

systemctl enable lightdm.service
echo "=== ubuntu-gui-ps4: done — reboot or: systemctl start lightdm ==="