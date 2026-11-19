#!/bin/bash
# Install official Discord (linux tar.gz) on psxitarch x86_64.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run: sudo bash $0" >&2
  exit 1
fi

sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true

# Do not bulk-upgrade curl/openssl on psxitarch (breaks libssl.so.1.1).
# Only ensure libgcc if Electron apps fail to start.
if [[ ! -e /usr/lib/libgcc_s.so.1 ]]; then
  yes "" | pacman -S --noconfirm --overwrite '*' libgcc 2>/dev/null || true
fi

DISCORD_USER="${SUDO_USER:-psxita}"
HOME_DIR="$(getent passwd "$DISCORD_USER" | cut -d: -f6)"
APP_ROOT="$HOME_DIR/Applications"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"
INSTALL_DIR="$APP_ROOT/Discord"
mkdir -p "$APP_ROOT" "$BIN_DIR" "$DESKTOP_DIR"
chown -R "$DISCORD_USER:$DISCORD_USER" "$APP_ROOT" "$HOME_DIR/.local"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TARBALL="${DISCORD_TARBALL:-}"
if [[ -n "$TARBALL" && -f "$TARBALL" ]]; then
  echo "Using local tarball: $TARBALL"
  cp "$TARBALL" "$TMP/Discord.tar.gz"
else
  API="https://discord.com/api/download?platform=linux&format=tar.gz"
  echo "Resolving Discord stable download…"
  URL="$(curl -fsSI "$API" | tr -d '\r' | awk -F': ' '/^[Ll]ocation:/{print $2}' | tail -1)"
  if [[ -z "$URL" ]]; then
    echo "Failed to resolve Discord download URL" >&2
    exit 1
  fi
  if [[ "$URL" == *installers/latest* ]]; then
    URL="$(curl -fsSI "$URL" | tr -d '\r' | awk -F': ' '/^[Ll]ocation:/{print $2}' | tail -1)"
  fi
  echo "Downloading $URL"
  runuser -u "$DISCORD_USER" -- curl -fL --retry 3 -o "$TMP/Discord.tar.gz" "$URL"
fi
rm -rf "$INSTALL_DIR"
runuser -u "$DISCORD_USER" -- mkdir -p "$INSTALL_DIR"
runuser -u "$DISCORD_USER" -- tar -xzf "$TMP/Discord.tar.gz" -C "$INSTALL_DIR" --strip-components=0
chmod +x "$INSTALL_DIR/Discord" "$INSTALL_DIR/Update" "$INSTALL_DIR/chrome-sandbox" 2>/dev/null || chmod +x "$INSTALL_DIR/Discord"

DISCORD_BIN="$INSTALL_DIR/Discord"
cat >"$BIN_DIR/discord" <<EOF
#!/bin/bash
exec "$DISCORD_BIN" --no-sandbox "\$@" &
EOF
chmod +x "$BIN_DIR/discord"
chown "$DISCORD_USER:$DISCORD_USER" "$BIN_DIR/discord"

cat >"$DESKTOP_DIR/discord.desktop" <<EOF
[Desktop Entry]
Name=Discord
Comment=Voice and text chat
Exec=$DISCORD_BIN --no-sandbox
Icon=$INSTALL_DIR/discord.png
Type=Application
Categories=Network;Chat;
StartupWMClass=discord
Terminal=false
EOF
chown "$DISCORD_USER:$DISCORD_USER" "$DESKTOP_DIR/discord.desktop"

grep -q '.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME_DIR/.bashrc"

echo "OK — launch: discord  (or Applications → Discord)"