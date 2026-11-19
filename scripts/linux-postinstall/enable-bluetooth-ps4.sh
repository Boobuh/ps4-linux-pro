#!/bin/bash
# PS4 psxitarch: restore JWM Bluetooth menu + Blueman (missing ~/.jwmrc is common). Run as root.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root only" >&2; exit 1; }

USER_NAME="${1:-psxita}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || { echo "no home for $USER_NAME" >&2; exit 1; }

locale_lang="$(grep -E '^LANG=' /etc/locale.conf 2>/dev/null | cut -d= -f2 | cut -d. -f1 | tr '-' '_')"
locale_lang="${locale_lang:-en_US}"
jwm_src="$HOME_DIR/.jwmrc-${locale_lang}"
[[ -f "$jwm_src" ]] || jwm_src="$HOME_DIR/.jwmrc-en_US"
[[ -f "$jwm_src" ]] || { echo "missing $jwm_src" >&2; exit 1; }

ln -sf "$jwm_src" "$HOME_DIR/.jwmrc"
chown -h "$USER_NAME:$USER_NAME" "$HOME_DIR/.jwmrc"

cat >/usr/local/bin/ps4-bluetooth-gui <<'EOF'
#!/bin/bash
set -euo pipefail
uid="$(id -u)"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
if [[ -z "${XAUTHORITY:-}" ]]; then
  auth="$(ls -t /tmp/serverauth.* 2>/dev/null | head -1 || true)"
  if [[ -n "$auth" ]]; then
    export XAUTHORITY="$auth"
  elif [[ -e "$HOME/.Xauthority" ]]; then
    export XAUTHORITY="$HOME/.Xauthority"
  fi
fi
exec blueman-manager "$@"
EOF
chmod 755 /usr/local/bin/ps4-bluetooth-gui

install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.local/share/applications"
cat >"$HOME_DIR/.local/share/applications/blueman-manager.desktop" <<'EOF'
[Desktop Entry]
Name=Bluetooth devices
Comment=Manage Bluetooth pairings
Exec=/usr/local/bin/ps4-bluetooth-gui
Icon=blueman
Terminal=false
Type=Application
Categories=Settings;
EOF

for jwm in "$HOME_DIR"/.jwmrc-*; do
  [[ -f "$jwm" ]] || continue
  sed -i 's/^[[:space:]]*blueman-applet[[:space:]]*$/       blueman-applet \&/' "$jwm"
  if ! grep -q polkit-gnome-authentication-agent-1 "$jwm"; then
    sed -i '/blueman-applet \&/a\       command -v polkit-gnome-authentication-agent-1 >/dev/null \&\& polkit-gnome-authentication-agent-1 \&' "$jwm"
  fi
done
chown "$USER_NAME:$USER_NAME" "$HOME_DIR"/.jwmrc-* 2>/dev/null || true

if command -v bluetoothctl >/dev/null; then
  bluetoothctl power on 2>/dev/null || true
  bluetoothctl pairable on 2>/dev/null || true
fi

echo "OK — log out/in (or JWM → Refresh menu). Bluetooth: ps4-bluetooth-gui or menu → Bluetooth devices."