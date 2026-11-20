#!/bin/bash
# PS4 psxitarch: stage pacman deps, then XFCE + Ubuntu look. Root only. Log: /var/log/ubuntu-gui-staged.log
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

LOG=/var/log/ubuntu-gui-staged.log
exec > >(tee -a "$LOG") 2>&1

echo "=== install-ubuntu-gui-staged: $(date) ==="

sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
rm -f /var/lib/pacman/db.lck
pkill -9 pacman gpg 2>/dev/null || true

if grep -q '^\[community\]' /etc/pacman.conf 2>/dev/null; then
  sed -i '/^\[community\]/,/^\[multilib\]/{ /^Include/ s/^/#/; /^\[community\]/ s/^/#/ }' /etc/pacman.conf
fi
if grep -q '^\[ps4\]' /etc/pacman.conf 2>/dev/null; then
  sed -i '/^\[ps4\]/,/^$/ s/^/#/' /etc/pacman.conf
fi
if ! grep -q '^SigLevel = Never' /etc/pacman.conf 2>/dev/null; then
  cp -a /etc/pacman.conf /etc/pacman.conf.bak-staged-gui
  sed -i 's/^SigLevel.*/SigLevel = Never\nLocalFileSigLevel = Never/' /etc/pacman.conf
fi
if [[ ! -f /etc/pacman.d/mirrorlist.staged-gui-bak ]]; then
  cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.staged-gui-bak
  cat >/etc/pacman.d/mirrorlist <<'MIR'
Server = https://archive.archlinux.org/repos/2021/09/07/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = http://mi.mirror.garr.it/mirrors/archlinux/$repo/os/$arch
MIR
fi

echo "--- phase 1: sync db ---"
pacman -Sy --noconfirm

echo "--- phase 2: XFCE libraries ---"
yes "" | pacman -S --noconfirm --needed \
  xfconf libxfce4ui libxfce4util exo garcon

echo "--- phase 3: XFCE desktop ---"
yes "" | pacman -S --noconfirm --needed \
  xfce4-session xfwm4 xfdesktop thunar xfce4-panel xfce4-settings xfce4-terminal \
  xfce4-power-manager xfce4-notifyd

echo "--- phase 4: session / policy / network ---"
yes "" | pacman -S --noconfirm --needed \
  lightdm lightdm-gtk-greeter polkit-gnome network-manager-applet \
  gtk-layer-shell elementary-icon-theme

echo "--- phase 5: Ubuntu look deps (no full -Syu) ---"
LOOK_OPTS=(gnome-themes-extra gtk-engine-murrine gtk-engines papirus-icon-theme
  ttf-ubuntu-font-family cantarell-fonts adwaita-icon-theme)
for p in "${LOOK_OPTS[@]}"; do
  pacman -Qi "$p" &>/dev/null && continue
  pacman -S --noconfirm --needed "$p" || echo "warn: skipped $p"
done

echo "--- phase 6: lightdm autologin + XFCE startx (keep JWM backup) ---"
LIGHTDM=/etc/lightdm/lightdm.conf
mkdir -p "$(dirname "$LIGHTDM")"
touch "$LIGHTDM"
if ! grep -q '^autologin-user=psxita' "$LIGHTDM" 2>/dev/null; then
  printf '\n[Seat:*]\nautologin-user=psxita\nautologin-session=xfce\n' >>"$LIGHTDM"
fi

XINIT=/home/psxita/.xinitrc
[[ -f "${XINIT}.jwm-backup" ]] || cp -a "$XINIT" "${XINIT}.jwm-backup" 2>/dev/null || \
  printf '%s\n' 'exec /usr/bin/jwm' >"${XINIT}.jwm-backup"
cat >"$XINIT" <<'EOF'
#!/bin/sh
# XFCE on psxitarch: use startxfce4 from console login (startx); not while replacing JWM remotely.
if [[ -n "${PS4_FORCE_XFCE:-}" ]] && command -v startxfce4 >/dev/null 2>&1; then
  exec startxfce4
fi
exec /usr/bin/jwm
EOF
chown psxita:psxita "$XINIT" "${XINIT}.jwm-backup"
chmod +x "$XINIT"

# Do not enable lightdm on psxitarch tty1 (fights startx); XFCE via startx first boot after logout.
systemctl disable lightdm.service 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/ubuntu-look-arch.sh" ]]; then
  PS4_SKIP_SYU=1 bash "$SCRIPT_DIR/ubuntu-look-arch.sh"
elif [[ -f /tmp/ubuntu-look-arch.sh ]]; then
  PS4_SKIP_SYU=1 bash /tmp/ubuntu-look-arch.sh
fi

touch /var/lib/ps4-ubuntu-gui-staged-done
echo "=== DONE $(date) — log out psxita or: systemctl restart getty@tty1 ==="
echo "JWM rollback: cp ~/.xinitrc.jwm-backup ~/.xinitrc"