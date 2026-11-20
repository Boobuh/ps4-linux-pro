#!/bin/bash
# Ubuntu wallpaper + JWM chrome (when XFCE/xfwm4 cannot run). Root on psxitarch.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

DESKTOP_USER="${DESKTOP_USER:-psxita}"
UHOME="/home/$DESKTOP_USER"
SCRIPT_DIR="${PS4_SCRIPT_DIR:-/tmp}"
WALL_LOCAL="${UBUNTU_WALLPAPER:-${SCRIPT_DIR}/assets/ubuntu-wallpaper.png}"
JWM_SRC="${JWM_TEMPLATE:-${SCRIPT_DIR}/assets/ubuntu-jwmrc-en_US.xml}"
BG_DIR="/usr/share/backgrounds/ubuntu"
WALL="$BG_DIR/ubuntu.png"

mkdir -p "$BG_DIR"
if [[ -f "$WALL_LOCAL" ]]; then
  cp -a "$WALL_LOCAL" "$WALL"
elif [[ -f /tmp/ubuntu-wallpaper.png ]]; then
  cp -a /tmp/ubuntu-wallpaper.png "$WALL"
else
  printf '%s\n' "warn: no wallpaper file — place ubuntu-wallpaper.png in assets/ or /tmp"
fi
mkdir -p "$UHOME/wallpapers"
WUSER="$UHOME/wallpapers/ubuntu.png"
rm -f "$UHOME/.ubuntu-wall.png" "$WUSER" 2>/dev/null || true
if [[ -f "$WALL_LOCAL" ]]; then
  cat "$WALL_LOCAL" >"$WUSER" || cp -a "$WALL_LOCAL" "$WUSER" || true
elif [[ -f "$WALL" ]]; then
  cat "$WALL" >"$WUSER" 2>/dev/null || cp -a "$WALL" "$WUSER" || true
fi
chown "$DESKTOP_USER:$DESKTOP_USER" "$WUSER" 2>/dev/null || true
chmod 644 "$WUSER" 2>/dev/null || true

pacman -Rdd --noconfirm feh 2>/dev/null || true
if [[ -f /tmp/libpng-1.6.37-3-x86_64.pkg.tar.zst ]]; then
  pacman -U --noconfirm /tmp/libpng-1.6.37-3-x86_64.pkg.tar.zst 2>/dev/null || true
fi

if [[ -f "$JWM_SRC" ]]; then
  for loc in en_US de_DE es_ES fr_FR it_IT; do
    cp -a "$JWM_SRC" "$UHOME/.jwmrc-${loc}"
  done
  ln -sf "$UHOME/.jwmrc-en_US" "$UHOME/.jwmrc"
  chown -h "$DESKTOP_USER:$DESKTOP_USER" "$UHOME/.jwmrc" "$UHOME/.jwmrc-"*
fi

mkdir -p "$UHOME/.config/gtk-3.0"
cat >"$UHOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adapta
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Ubuntu 11
EOF
chown -R "$DESKTOP_USER:$DESKTOP_USER" "$UHOME/.config/gtk-3.0"

cat >"$UHOME/.xinitrc" <<'EOF'
#!/bin/sh
xset -dpms 2>/dev/null || true
xset s off 2>/dev/null || true
exec /usr/bin/jwm
EOF
chmod +x "$UHOME/.xinitrc"
chown "$DESKTOP_USER:$DESKTOP_USER" "$UHOME/.xinitrc"

AUTH=$(ls -t /tmp/serverauth.* 2>/dev/null | head -1)
if [[ -n "$AUTH" ]] && pgrep -u "$DESKTOP_USER" -x jwm >/dev/null 2>&1; then
  runuser -u "$DESKTOP_USER" -- env DISPLAY=:0 XAUTHORITY="$AUTH" \
    pcmanfm --desktop --set-wallpaper="$WALL" 2>/dev/null || true
  runuser -u "$DESKTOP_USER" -- env DISPLAY=:0 XAUTHORITY="$AUTH" jwm -restart 2>/dev/null || true
else
  pkill -9 -u "$DESKTOP_USER" jwm Xorg startx 2>/dev/null || true
  sleep 1
  rm -f /tmp/.X0-lock 2>/dev/null || true
  systemctl restart getty@tty1.service
fi

echo "=== ubuntu-jwm-look-ps4: wallpaper=$WALL jwmrc restored ==="