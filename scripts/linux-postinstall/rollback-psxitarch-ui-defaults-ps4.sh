#!/bin/bash
# Roll back PS4-Linux-Pro Ubuntu/JWM UI tweaks to stock psxitarch defaults. Root only.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo -i)" >&2; exit 1; }

U="${DESKTOP_USER:-psxita}"
HOME_DIR="/home/$U"
BACKUP_DIR="${HOME_DIR}/.ps4-linux-pro-ui-backup"
SYSTEM_JWM="/etc/system.jwmrc"
FULL_RESTART="${FULL_RESTART:-1}"

echo "=== rollback-psxitarch-ui-defaults-ps4 $(date) ==="

systemctl disable ps4-ubuntu-gui-install.service 2>/dev/null || true
systemctl stop ps4-ubuntu-gui-install.service 2>/dev/null || true
rm -f /var/lib/ps4-ubuntu-gui-installed /var/lib/pacman/db.lck 2>/dev/null || true

# --- JWM: prefer snapshot taken before our tweaks, else distro system.jwmrc ---
if [[ -d "$BACKUP_DIR" ]] && [[ -f "$BACKUP_DIR/.jwmrc-en_US" ]]; then
  echo "restore JWM from $BACKUP_DIR"
  for f in "$BACKUP_DIR"/.jwmrc-*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    cp -a "$f" "$HOME_DIR/$base"
  done
  if [[ -L "$BACKUP_DIR/.jwmrc" ]] || [[ -f "$BACKUP_DIR/.jwmrc" ]]; then
    cp -a "$BACKUP_DIR/.jwmrc" "$HOME_DIR/.jwmrc" 2>/dev/null || true
  fi
else
  if [[ ! -r "$SYSTEM_JWM" ]]; then
    echo "missing $SYSTEM_JWM — cannot restore stock JWM" >&2
    exit 1
  fi
  echo "restore JWM from $SYSTEM_JWM (psxitarch stock)"
  for loc in en_US de_DE es_ES fr_FR it_IT; do
    cp -a "$SYSTEM_JWM" "$HOME_DIR/.jwmrc-${loc}"
  done
  ln -sf "$HOME_DIR/.jwmrc-en_US" "$HOME_DIR/.jwmrc"
fi

# --- xinitrc: backup from XFCE install path, else minimal stock ---
if [[ -f "$HOME_DIR/.xinitrc.jwm-backup" ]]; then
  cp -a "$HOME_DIR/.xinitrc.jwm-backup" "$HOME_DIR/.xinitrc"
elif [[ -f "$BACKUP_DIR/.xinitrc" ]]; then
  cp -a "$BACKUP_DIR/.xinitrc" "$HOME_DIR/.xinitrc"
else
  cat >"$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
exec /usr/bin/jwm
EOF
fi
chmod +x "$HOME_DIR/.xinitrc"

# --- GTK theme overrides we added (ubuntu-jwm-look / ubuntu-look-arch) ---
if [[ -f "$BACKUP_DIR/gtk-3.0-settings.ini" ]]; then
  mkdir -p "$HOME_DIR/.config/gtk-3.0"
  cp -a "$BACKUP_DIR/gtk-3.0-settings.ini" "$HOME_DIR/.config/gtk-3.0/settings.ini"
elif [[ -f "$HOME_DIR/.config/gtk-3.0/settings.ini" ]]; then
  mv -f "$HOME_DIR/.config/gtk-3.0/settings.ini" \
    "$HOME_DIR/.config/gtk-3.0/settings.ini.ps4-linux-pro.bak" 2>/dev/null || true
fi

chown -R "$U:$U" "$HOME_DIR/.jwmrc"* "$HOME_DIR/.xinitrc" "$HOME_DIR/.config" 2>/dev/null || true
chown -h "$U:$U" "$HOME_DIR/.jwmrc" 2>/dev/null || true

if ! jwm -p -f "$HOME_DIR/.jwmrc-en_US" 2>/dev/null; then
  echo "warn: jwm -p reported issues — still restarting session"
fi

if [[ "$FULL_RESTART" == "1" ]]; then
  pkill -9 -u "$U" jwm Xorg startx 2>/dev/null || true
  sleep 1
  rm -f /tmp/.X0-lock 2>/dev/null || true
  systemctl restart getty@tty1.service
fi

cat <<'EOF'

OK — stock psxitarch JWM UI (bottom tray from /etc/system.jwmrc, plain startx).
Custom wallpaper under ~/wallpapers and /usr/share/backgrounds/ubuntu are left in place (delete manually if unwanted).
Re-apply Ubuntu look: bash ubuntu-jwm-look-ps4.sh
Re-apply full stack: bash apply-psxitarch-best-practices-ps4.sh

EOF