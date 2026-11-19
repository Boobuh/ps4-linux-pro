#!/bin/bash
# Battle.net on psxitarch via Wine (no native Linux app). Run on PS4 desktop or SSH.
# Does NOT upgrade openssl/curl (see repair-openssl-psxitarch.sh if SSH broke).
set -euo pipefail

GAME_USER="${SUDO_USER:-${GAME_USER:-psxita}}"
if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -u "$GAME_USER" bash "$0"
  exit
fi

HOME_DIR="$(getent passwd "$GAME_USER" | cut -d: -f6)"
GAMEDIR="$HOME_DIR/Games/battlenet"
SETUP="${BATTLENET_SETUP:-$HOME_DIR/Downloads/Battle.net-Setup.exe}"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"

if [[ ! -f "$SETUP" ]]; then
  echo "Missing installer. Copy Battle.net-Setup.exe to:" >&2
  echo "  $SETUP" >&2
  echo "or set BATTLENET_SETUP=/path/to/Battle.net-Setup.exe" >&2
  exit 1
fi

if ! command -v wine >/dev/null 2>&1 && ! command -v wine64 >/dev/null 2>&1; then
  echo "Wine is not installed. On psxitarch install manually (avoid openssl upgrades):" >&2
  echo "  sudo pacman -S --needed wine wine-gecko wine-mono" >&2
  echo "  # 32-bit deps often required: lib32-* via multilib — see Lutris Battle.Net.md" >&2
  exit 1
fi

WINE="$(command -v wine64 || command -v wine)"
export WINEPREFIX="$GAMEDIR"
export WINEARCH=win64
export WINE_SIMULATE_WRITECOPY=1
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-locationapi=d}"
export DXVK_HUD="${DXVK_HUD:-}"
mkdir -p "$GAMEDIR" "$BIN_DIR" "$DESKTOP_DIR"

if [[ ! -d "$GAMEDIR/drive_c" ]]; then
  echo "Creating Wine prefix at $GAMEDIR …"
  "$WINE" wineboot --init
fi

echo "Running Blizzard installer (use the GUI; close login when done — do not sign in yet)…"
"$WINE" "$SETUP"

LAUNCHER="$GAMEDIR/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
if [[ ! -f "$LAUNCHER" ]]; then
  LAUNCHER="$GAMEDIR/drive_c/Program Files/Battle.net/Battle.net Launcher.exe"
fi
if [[ ! -f "$LAUNCHER" ]]; then
  echo "Installer finished but Launcher.exe not found under $GAMEDIR" >&2
  exit 1
fi

cat >"$BIN_DIR/battlenet" <<EOF
#!/bin/bash
export WINEPREFIX="$GAMEDIR"
export WINEARCH=win64
export WINE_SIMULATE_WRITECOPY=1
export WINEDLLOVERRIDES="locationapi=d"
exec "$WINE" "$LAUNCHER" "\$@" &
EOF
chmod +x "$BIN_DIR/battlenet"

cat >"$DESKTOP_DIR/battlenet.desktop" <<EOF
[Desktop Entry]
Name=Battle.net
Comment=Blizzard app (Wine)
Exec=env WINEPREFIX=$GAMEDIR WINEARCH=win64 WINE_SIMULATE_WRITECOPY=1 WINEDLLOVERRIDES=locationapi=d $WINE "$LAUNCHER"
Type=Application
Categories=Game;
StartupWMClass=battle.net.exe
Terminal=false
EOF

grep -q '.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME_DIR/.bashrc"
chown -R "$GAME_USER:$GAME_USER" "$GAMEDIR" "$BIN_DIR" "$DESKTOP_DIR" "$HOME_DIR/.bashrc" 2>/dev/null || true

echo "OK — launch: battlenet"
echo "Prefix: $GAMEDIR"