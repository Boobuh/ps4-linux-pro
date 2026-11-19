#!/bin/bash
# Copy installers + scripts to a USB stick for PS4 console (when SSH is down).
# Usage: DISK=/Volumes/MYUSB ./bundle-to-ps4-console.sh
set -euo pipefail

DISK="${DISK:?Set DISK to mount point, e.g. DISK=/Volumes/USB}"
DEST="$DISK/ps4-linux-bundle"
mkdir -p "$DEST"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cp "$ROOT/scripts/linux-postinstall/"{repair-openssl-psxitarch.sh,restore-hdmi-ps4-arch.sh,install-discord-from-tarball.sh,install-battlenet-wine-ps4.sh} "$DEST/"

for f in /tmp/Discord-ps4.tar.gz /tmp/Battle.net-Setup.exe; do
  [[ -f "$f" ]] && cp "$f" "$DEST/" || echo "Skip missing $f"
done

cat >"$DEST/README.txt" <<'EOF'
PS4 Arch — offline install (local terminal as root/psxita)

1) Fix SSH/openssl (if Mac cannot ssh):
   sudo bash repair-openssl-psxitarch.sh

2) Black HDMI — try psxitarch hotkeys first: Alt+F11 then Alt+F12 (USB keyboard).
   Then: sudo bash restore-hdmi-ps4-arch.sh

4) Discord:
   sudo -u psxita bash install-discord-from-tarball.sh ./Discord-ps4.tar.gz

5) Battle.net (needs wine installed first):
   cp Battle.net-Setup.exe ~psxita/Downloads/
   sudo -u psxita BATTLENET_SETUP=~/Downloads/Battle.net-Setup.exe bash install-battlenet-wine-ps4.sh

Battle.net is Windows-only; use Wine on XFCE. Gaming performance on PS4 is limited.
EOF

echo "Wrote $DEST"
ls -la "$DEST"