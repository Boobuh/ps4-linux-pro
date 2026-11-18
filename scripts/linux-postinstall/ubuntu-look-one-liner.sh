# Paste entire block into Arch terminal on PS4 (Konsole), with sudo/root.
sudo bash -eux <<'EOS'
pacman -Syu --noconfirm || true
pacman -S --noconfirm --needed gnome-themes-extra gtk-engine-murrine gtk-engines \
  papirus-icon-theme ttf-ubuntu-font-family cantarell-fonts adwaita-icon-theme \
  2>/dev/null || true
(pacman -S --noconfirm --needed yaru-gtk-theme yaru-icon-theme 2>/dev/null) || THEME=Adwaita-dark
THEME="${THEME:-Yaru-dark}"
ICON="${ICON:-Yaru}"
command -v xfconf-query >/dev/null && {
  xfconf-query -c xsettings -p /Net/ThemeName -s "$THEME" 2>/dev/null || xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita-dark
  xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICON" 2>/dev/null || xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus
  xfconf-query -c xsettings -p /Gtk/FontName -s "Ubuntu 11" 2>/dev/null || true
}
command -v gsettings >/dev/null && {
  gsettings set org.gnome.desktop.interface gtk-theme "$THEME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme "$ICON" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name "Ubuntu 11" 2>/dev/null || true
}
mkdir -p /etc/skel/.config/gtk-3.0
printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-font-name=Ubuntu 11\n' "$THEME" "$ICON" \
  >/etc/skel/.config/gtk-3.0/settings.ini
for d in /root /home/*; do
  [ -d "$d/.config" ] || mkdir -p "$d/.config/gtk-3.0"
  cp /etc/skel/.config/gtk-3.0/settings.ini "$d/.config/gtk-3.0/" 2>/dev/null || true
done
echo "Ubuntu look applied — log out and back in."
EOS