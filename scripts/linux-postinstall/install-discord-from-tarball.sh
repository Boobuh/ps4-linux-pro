#!/bin/bash
# Extract official Discord tar.gz under ~/Applications/Discord (no pacman).
set -euo pipefail

TARBALL="${1:?Usage: $0 /path/to/Discord.tar.gz}"

USER_NAME="${SUDO_USER:-psxita}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
APP_ROOT="$HOME_DIR/Applications"
INSTALL_DIR="$APP_ROOT/Discord"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"

mkdir -p "$APP_ROOT" "$BIN_DIR" "$DESKTOP_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/Discord"

cat >"$BIN_DIR/discord" <<EOF
#!/bin/bash
exec "$INSTALL_DIR/Discord" --no-sandbox "\$@" &
EOF
chmod +x "$BIN_DIR/discord"

cat >"$DESKTOP_DIR/discord.desktop" <<EOF
[Desktop Entry]
Name=Discord
Exec=$INSTALL_DIR/Discord --no-sandbox
Icon=$INSTALL_DIR/discord.png
Type=Application
Categories=Network;Chat;
StartupWMClass=discord
Terminal=false
EOF

grep -q '.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null || echo 'export PATH="\$HOME/.local/bin:\$PATH"' >>"$HOME_DIR/.bashrc"
chown -R "$USER_NAME:$USER_NAME" "$APP_ROOT" "$HOME_DIR/.local" "$HOME_DIR/.bashrc" 2>/dev/null || true

echo "Installed. Run: discord"