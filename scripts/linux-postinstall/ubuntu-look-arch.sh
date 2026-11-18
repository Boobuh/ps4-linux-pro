#!/bin/bash
# Make psxitarch (Arch) *look* like Ubuntu — themes/fonts, not a full Ubuntu base.
# Run ON THE PS4 as root after first desktop boot:  bash ubuntu-look-arch.sh
# Needs network (pacman). GNOME Shell is heavy on PS4; default path themes XFCE/GTK.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo -i)" >&2
  exit 1
fi

echo "=== PS4 Linux — Ubuntu-style desktop (Arch) ==="

pacman -Syu --noconfirm || true

# GTK / icons / fonts (official + community)
PACKAGES=(
  gnome-themes-extra
  gtk-engine-murrine
  gtk-engines
  papirus-icon-theme
  ttf-ubuntu-font-family
  cantarell-fonts
  adwaita-icon-theme
)

for p in "${PACKAGES[@]}"; do
  if ! pacman -Qi "$p" &>/dev/null; then
    pacman -S --noconfirm --needed "$p" || echo "warn: optional package $p skipped"
  fi
done

# Yaru (Ubuntu 22.04+ look) — often in community or AUR
if pacman -Ss '^extra/yaru-' &>/dev/null; then
  pacman -S --noconfirm --needed yaru-gtk-theme yaru-icon-theme 2>/dev/null || true
elif command -v yay &>/dev/null; then
  echo "Installing Yaru from AUR (yay)…"
  yay -S --noconfirm --needed yaru-gtk-theme yaru-icon-theme || true
else
  echo "Yaru not in repos — using Adwaita + Papirus (close enough without AUR)"
  THEME="Adwaita"
  ICON="Papirus"
fi

THEME="${THEME:-Yaru-dark}"
ICON="${ICON:-Yaru}"

# XFCE (common on lightweight psxitarch)
if command -v xfconf-query &>/dev/null; then
  xfconf-query -c xsettings -p /Net/ThemeName -s "$THEME" 2>/dev/null || \
    xfconf-query -c xsettings -p /Net/ThemeName -s "Adwaita-dark"
  xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICON" 2>/dev/null || \
    xfconf-query -c xsettings -p /Net/IconThemeName -s "Papirus"
  xfconf-query -c xsettings -p /Gtk/FontName -s "Ubuntu 11" 2>/dev/null || true
  xfconf-query -c xfwm4 -p /general/theme -s "Yaru" 2>/dev/null || \
    xfconf-query -c xfwm4 -p /general/theme -s "Default" 2>/dev/null || true
  echo "XFCE: theme applied (log out/in or restart panel if needed)"
fi

# GNOME / MATE via gsettings
if command -v gsettings &>/dev/null; then
  gsettings set org.gnome.desktop.interface gtk-theme "${THEME}" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme "${ICON}" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name "Ubuntu 11" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme "Yaru" 2>/dev/null || true
fi

# Global GTK3 (apps that ignore XFCE)
mkdir -p /etc/skel/.config/gtk-3.0
cat >/etc/skel/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=$THEME
gtk-icon-theme-name=$ICON
gtk-font-name=Ubuntu 11
EOF
for d in /root /home/*; do
  [[ -d "$d" ]] || continue
  mkdir -p "$d/.config/gtk-3.0"
  cp /etc/skel/.config/gtk-3.0/settings.ini "$d/.config/gtk-3.0/" 2>/dev/null || true
done

echo "Done. Reboot or log out/in. For full Ubuntu (GNOME Shell), see docs/PS4-LINUX-UBUNTU-DESKTOP-LOOK.md"