#!/bin/bash
# Install Cursor IDE (official AppImage) on psxitarch x86_64.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run: sudo bash $0" >&2
  exit 1
fi

sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true

DEPS=(
  fuse2
  gtk3
  nss
  alsa-lib
  libxss
  libxtst
  xdg-utils
  wget
  noto-fonts
)
pacman -S --noconfirm --needed "${DEPS[@]}"

CURSOR_USER="${SUDO_USER:-psxita}"
HOME_DIR="$(getent passwd "$CURSOR_USER" | cut -d: -f6)"
APP_DIR="$HOME_DIR/Applications"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"
mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"
chown -R "$CURSOR_USER:$CURSOR_USER" "$HOME_DIR/Applications" "$HOME_DIR/.local"

APPIMAGE="$APP_DIR/Cursor.AppImage"
API_URL="https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable"

echo "Resolving Cursor AppImage URL…"
URL="$(curl -fsSL "$API_URL" | sed -n 's/.*"downloadUrl":"\([^"]*\)".*/\1/p')"
if [[ -z "$URL" ]]; then
  echo "Failed to resolve downloadUrl from Cursor API" >&2
  exit 1
fi
echo "Downloading Cursor AppImage (x64)…"
runuser -u "$CURSOR_USER" -- curl -fL --retry 3 -o "${APPIMAGE}.part" "$URL"
mv "${APPIMAGE}.part" "$APPIMAGE"
chmod +x "$APPIMAGE"
chown "$CURSOR_USER:$CURSOR_USER" "$APPIMAGE"

cat >"$BIN_DIR/cursor" <<EOF
#!/bin/bash
exec "$APPIMAGE" --no-sandbox "\$@" >/dev/null 2>&1 &
EOF
chmod +x "$BIN_DIR/cursor"
chown "$CURSOR_USER:$CURSOR_USER" "$BIN_DIR/cursor"

cat >"$DESKTOP_DIR/cursor.desktop" <<EOF
[Desktop Entry]
Name=Cursor
Comment=AI IDE
Exec=$APPIMAGE --no-sandbox %F
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Cursor
EOF
chown "$CURSOR_USER:$CURSOR_USER" "$DESKTOP_DIR/cursor.desktop"

grep -q '.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME_DIR/.bashrc"

echo "OK — log in as $CURSOR_USER, open Terminal or app menu: cursor"
echo "First launch may be slow on PS4 (Electron). Use --no-sandbox if needed."