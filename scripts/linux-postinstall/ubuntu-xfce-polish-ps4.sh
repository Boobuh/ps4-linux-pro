#!/bin/bash
# Polish psxitarch XFCE to feel like Ubuntu (themes, panel, wallpaper). Run as root on console.
# Safe on glibc 2.33: no full -Syu; whisker via --assume-installed accountsservice if needed.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root only" >&2; exit 1; }

DESKTOP_USER="${DESKTOP_USER:-psxita}"
UHOME="/home/$DESKTOP_USER"
XDG_CFG="$UHOME/.config"
CHANNEL="$XDG_CFG/xfce4/xfconf/xfce-perchannel-xml"
BG_DIR="/usr/share/backgrounds/ubuntu"
WALL="$BG_DIR/ubuntu-default.jpg"

echo "=== ubuntu-xfce-polish-ps4: start $(date) ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! id "$DESKTOP_USER" &>/dev/null; then
  echo "user $DESKTOP_USER not found" >&2
  exit 1
fi

THEME_PKGS=(adapta-gtk-theme papirus-icon-theme ttf-ubuntu-font-family gtk-engine-murrine)
OPTIONAL_PKGS=(gnome-themes-extra cantarell-fonts)
install_pkg() {
  local p=$1
  if pacman -Qi "$p" &>/dev/null 2>&1; then
    return 0
  fi
  if command -v timeout &>/dev/null; then
    timeout 45 pacman -S --noconfirm --needed "$p" \
      --ignore libgcc,libstdc++,glibc 2>/dev/null || echo "warn: optional $p skipped"
  else
    pacman -S --noconfirm --needed "$p" \
      --ignore libgcc,libstdc++,glibc 2>/dev/null || echo "warn: optional $p skipped"
  fi
}
for p in "${THEME_PKGS[@]}"; do
  install_pkg "$p"
done
for p in "${OPTIONAL_PKGS[@]}"; do
  install_pkg "$p" || true
done

# Whisker 2.10+ breaks xfce4-panel 4.16 (plugins silently fail). Use applicationsmenu on PS4.
if pacman -Qi xfce4-whiskermenu-plugin &>/dev/null; then
  pacman -Rdd --noconfirm xfce4-whiskermenu-plugin 2>/dev/null || true
fi

mkdir -p "$BG_DIR" "$CHANNEL" "$XDG_CFG/gtk-3.0" "$XDG_CFG/gtk-2.0"

if [[ ! -s "$WALL" ]]; then
  for url in \
    "https://assets.ubuntu.com/v1/40662cf1-d93a-4b21-b4f8-b9a47dd0b148-Warty-final-ubuntu-default-orange-redscale-1080p.png" \
    "https://raw.githubusercontent.com/CanonicalLtd/desktop-icons-preview/master/src/wallpapers/916684.jpg"; do
  if curl -fL --max-time 90 -o "$WALL.part" "$url" 2>/dev/null && [[ -s "$WALL.part" ]]; then
      mv "$WALL.part" "$WALL"
      break
    fi
  done
  rm -f "$WALL.part"
fi
if [[ ! -s "$WALL" ]]; then
  WALL=""
fi

cat >"$XDG_CFG/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adapta
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Ubuntu 11
gtk-cursor-theme-name=Adwaita
gtk-primary-button-warps-slider=0
gtk-button-images=0
gtk-menu-images=0
EOF

cat >"$XDG_CFG/gtk-2.0/gtkrc" <<'EOF'
gtk-theme-name="Adapta"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Ubuntu 11"
EOF

cat >"$CHANNEL/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adapta"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="FontName" type="string" value="Ubuntu 11"/>
    <property name="DoubleClickTime" type="int" value="250"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Ubuntu 11"/>
    <property name="MonospaceFontName" type="string" value="Ubuntu Mono 11"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
EOF

cat >"$CHANNEL/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
    <property name="button_layout" type="string" value="O|CHM|W"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="box_look" type="bool" value="true"/>
    <property name="title_font" type="string" value="Ubuntu Bold 9"/>
    <property name="click_to_focus" type="bool" value="true"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="placement_ratio" type="int" value="20"/>
    <property name="show_popup_shadow" type="bool" value="true"/>
  </property>
</channel>
EOF

cat >"$CHANNEL/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorsdp1" type="empty">
        <property name="monitor0" type="empty">
          <property name="workspace0" type="empty">
            <property name="color-style" type="int" value="0"/>
            <property name="image-style" type="int" value="5"/>
            <property name="rgba1" type="array" type="double">
              <value type="double" value="0.188235"/>
              <value type="double" value="0.039216"/>
              <value type="double" value="0.141176"/>
            </property>
            <property name="rgba2" type="array" type="double">
              <value type="double" value="0.913725"/>
              <value type="double" value="0.329412"/>
              <value type="double" value="0.125490"/>
            </property>
          </property>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="0"/>
  </property>
</channel>
EOF
if [[ -n "$WALL" && -f "$WALL" ]]; then
  # Optional image when download succeeded.
  sed -i "s|image-style\" type=\"int\" value=\"5\"|image-style\" type=\"int\" value=\"5\"/>\n            <property name=\"last-image\" type=\"string\" value=\"$WALL\"|" \
    "$CHANNEL/xfce4-desktop.xml" 2>/dev/null || true
fi

rm -f "$CHANNEL"/*.new 2>/dev/null || true
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml /etc/xdg/xfce4/panel

cat >"$CHANNEL/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=12;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="22"/>
      <property name="size" type="uint" value="36"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-alpha" type="uint" value="100"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
      <property name="show-handle" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-5" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-6" type="string" value="clock">
      <property name="digital-format" type="string" value="%a %d %b, %H:%M"/>
      <property name="timezone" type="string" value=""/>
    </property>
    <property name="plugin-7" type="string" value="actions"/>
  </property>
</channel>
EOF

cp -a "$CHANNEL/xfce4-panel.xml" /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
cp -a "$CHANNEL/xfce4-panel.xml" /etc/xdg/xfce4/panel/default.xml

for owned in gtk-3.0 gtk-2.0 xfce4; do
  chown -R "$DESKTOP_USER:$DESKTOP_USER" "$XDG_CFG/$owned" 2>/dev/null || true
done

if [[ "${PS4_SKIP_PANEL_RESTART:-0}" != "1" ]]; then
  if [[ -x "$SCRIPT_DIR/restart-xfce-session-ps4.sh" ]]; then
    bash "$SCRIPT_DIR/restart-xfce-session-ps4.sh"
  elif [[ -x /tmp/restart-xfce-session-ps4.sh ]]; then
    bash /tmp/restart-xfce-session-ps4.sh
  fi
fi

# Merge gtk skel for new users
mkdir -p /etc/skel/.config/gtk-3.0
cp -a "$XDG_CFG/gtk-3.0/settings.ini" /etc/skel/.config/gtk-3.0/ 2>/dev/null || true

if [[ ! -f "$UHOME/.xinitrc" ]] || ! grep -q xfce4-session "$UHOME/.xinitrc" 2>/dev/null; then
  cat >"$UHOME/.xinitrc" <<'EOF'
#!/bin/sh
if test -z "$DBUS_SESSION_BUS_ADDRESS"; then
  eval "$(dbus-launch --sh-syntax)"
fi
command -v polkit-gnome-authentication-agent-1 >/dev/null &&
  polkit-gnome-authentication-agent-1 &
export GTK_THEME=Adapta
export XDG_CURRENT_DESKTOP=XFCE
export XDG_MENU_PREFIX=xfce-
exec xfce4-session
EOF
  chmod +x "$UHOME/.xinitrc"
  chown "$DESKTOP_USER:$DESKTOP_USER" "$UHOME/.xinitrc"
fi

if pgrep -u "$DESKTOP_USER" xfce4-panel >/dev/null 2>&1; then
  runuser -u "$DESKTOP_USER" -- env DISPLAY=:0 xfdesktop --reload 2>/dev/null || true
  echo "hint: restart X on tty1 (logout or: pkill -u $DESKTOP_USER xfce4-session) to apply panel whisker menu"
fi

echo "=== ubuntu-xfce-polish-ps4: done ==="