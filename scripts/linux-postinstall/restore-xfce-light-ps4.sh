#!/bin/bash
# XFCE desktop without xfwm4 (Openbox WM) — for PS4 when xfwm4 bus-errors but X still runs.
# Does not full -Syu. Run as root.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

DESKTOP_USER="${DESKTOP_USER:-psxita}"
UHOME="/home/$DESKTOP_USER"

if ! pacman -Qi openbox &>/dev/null; then
  pacman -S --noconfirm --needed openbox \
    --ignore libgcc,libstdc++,glibc 2>/dev/null || echo "warn: openbox install failed"
fi

mkdir -p "$UHOME/.config/autostart"
cat >"$UHOME/.config/autostart/xfdesktop.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=xfdesktop
Exec=xfdesktop
OnlyShowIn=XFCE;
EOF
cat >"$UHOME/.config/autostart/xfce4-panel.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=xfce4-panel
Exec=xfce4-panel
OnlyShowIn=XFCE;
EOF

cat >"$UHOME/.xinitrc" <<'EOF'
#!/bin/sh
if test -z "$DBUS_SESSION_BUS_ADDRESS"; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi
command -v polkit-gnome-authentication-agent-1 >/dev/null &&
  polkit-gnome-authentication-agent-1 &
export GTK_THEME=Adapta
export XDG_CURRENT_DESKTOP=XFCE
export XDG_MENU_PREFIX=xfce-
xset -dpms 2>/dev/null || true
xset s off 2>/dev/null || true
xfdesktop --disable-wm-check &
xfce4-panel &
if command -v openbox >/dev/null 2>&1; then
  exec openbox
fi
exec xfwm4
EOF
chmod +x "$UHOME/.xinitrc"
chown "$DESKTOP_USER:$DESKTOP_USER" "$UHOME/.xinitrc" "$UHOME/.config/autostart"/*.desktop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/ubuntu-xfce-polish-ps4.sh" ]]; then
  PS4_SKIP_PANEL_RESTART=1 bash "$SCRIPT_DIR/ubuntu-xfce-polish-ps4.sh" || true
fi

if [[ -x "$SCRIPT_DIR/restart-xfce-session-ps4.sh" ]]; then
  bash "$SCRIPT_DIR/restart-xfce-session-ps4.sh"
else
  pkill -9 -u "$DESKTOP_USER" Xorg jwm startx xfce4-session 2>/dev/null || true
  sleep 2
  rm -f /tmp/.X0-lock 2>/dev/null || true
  systemctl restart getty@tty1.service
fi

echo "=== restore-xfce-light-ps4: done (Openbox + XFCE panel/desktop) ==="