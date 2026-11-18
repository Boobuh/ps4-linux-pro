#!/bin/sh
# Serve post-install scripts over HTTP for PS4 Linux (curl from Arch — no SSH/FTP).
# Usage: tools/ps4-linux-serve-scripts.sh [port]
# On PS4 Linux terminal:  curl -fsSL "http://<mac-ip>:8766/ubuntu-look-arch.sh" | sudo bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-8766}"
DIR="$ROOT/scripts/linux-postinstall"
LAN="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"
echo "Serving $DIR on http://${LAN}:${PORT}/"
echo ""
echo "On PS4 Linux (Terminal), run ONE of:"
echo "  curl -fsSL \"http://${LAN}:${PORT}/ubuntu-look-arch.sh\" | sudo bash"
echo "  curl -fsSL \"http://${LAN}:${PORT}/ubuntu-look-one-liner.sh\" | sudo bash"
echo ""
echo "Ctrl+C to stop."
cd "$DIR"
exec python3 -m http.server "$PORT" --bind 0.0.0.0