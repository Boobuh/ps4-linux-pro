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

# Stale keys / slow Arch.img: avoid blocking gpg keyserver fetch (hangs HDMI session).
if ! grep -q '^SigLevel = Never' /etc/pacman.conf 2>/dev/null; then
  cp -a /etc/pacman.conf /etc/pacman.conf.bak-ubuntu-gui
  sed -i 's/^SigLevel.*/SigLevel = Never\nLocalFileSigLevel = Never/' /etc/pacman.conf
fi
if [[ ! -s /etc/pacman.d/mirrorlist.ubuntu-gui-bak ]]; then
  cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.ubuntu-gui-bak 2>/dev/null || true
  cat >/etc/pacman.d/mirrorlist <<'MIR'
Server = https://archive.archlinux.org/repos/2021/09/07/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = http://mi.mirror.garr.it/mirrors/archlinux/$repo/os/$arch
MIR
fi
pacman -Sy --noconfirm

DEFER_LEGACY_REMOVE="${DEFER_LEGACY_REMOVE:-1}"
if [[ "$DEFER_LEGACY_REMOVE" == "0" ]]; then
  pacman -Rdd --noconfirm pcmanfm libfm-gtk2 2>/dev/null || true
  for legacy in gst-plugins-base gst-plugins-good gst-libav parole; do
    pacman -Rdd --noconfirm "$legacy" 2>/dev/null || true
  done
else
  echo "defer: pcmanfm/jwm stay until reboot (DEFER_LEGACY_REMOVE=0 to remove now)"
fi

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
if [[ -x "$SCRIPT_DIR/ubuntu-xfce-polish-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/ubuntu-xfce-polish-ps4.sh"
elif [[ -x /tmp/ubuntu-xfce-polish-ps4.sh ]]; then
  bash /tmp/ubuntu-xfce-polish-ps4.sh
elif [[ -x "$SCRIPT_DIR/ubuntu-look-arch.sh" ]]; then
  PS4_SKIP_SYU=1 bash "$SCRIPT_DIR/ubuntu-look-arch.sh"
fi

systemctl enable lightdm.service 2>/dev/null || true
# Until LightDM takes tty1, offer XFCE via startx.
XINIT=/home/psxita/.xinitrc
if [[ ! -f "${XINIT}.jwm-backup" ]]; then
  cp -a "$XINIT" "${XINIT}.jwm-backup" 2>/dev/null || echo 'exec /usr/bin/jwm' >"${XINIT}.jwm-backup"
fi
cat >"$XINIT" <<'EOF'
#!/bin/sh
if command -v startxfce4 >/dev/null 2>&1; then
  exec dbus-launch --exit-with-session startxfce4
fi
exec /usr/bin/jwm
EOF
chown psxita:psxita "$XINIT" "${XINIT}.jwm-backup" 2>/dev/null || true
chmod +x "$XINIT"

if [[ -x /home/psxita/Applications/enable-bluetooth-ps4.sh ]] || [[ -x /usr/local/sbin/enable-bluetooth-ps4.sh ]]; then
  /usr/local/sbin/enable-bluetooth-ps4.sh psxita 2>/dev/null || true
fi

echo "=== ubuntu-gui-ps4: done — reboot Linux (recommended) for LightDM; or log out/in for XFCE via startx ==="
echo "If HDMI goes black: SSH and run  recover-black-screen-ps4.sh"