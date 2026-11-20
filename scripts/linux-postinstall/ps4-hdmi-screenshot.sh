#!/bin/bash
# What you see on HDMI: grab /dev/fb0 (works without scrot/X). Run as root on psxitarch.
# Copy /tmp/ps4-fb.raw to Mac and run: tools/ps4-linux-fb-to-png.py (or polish workflow below).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

FB=/dev/fb0
OUT=/tmp/ps4-fb.raw
PNG=/tmp/ps4-hdmi.png

if [[ ! -r "$FB" ]]; then
  echo "no $FB" >&2
  exit 1
fi

VS="$(tr ',' ' ' < /sys/class/graphics/fb0/virtual_size)"
BPP="$(cat /sys/class/graphics/fb0/bits_per_pixel)"
read -r W H <<<"$VS"

BYTES=$((W * H * BPP / 8))
echo "fb0: ${W}x${H} ${BPP}bpp -> ${BYTES} bytes"

if ! head -c "$BYTES" "$FB" >"$OUT" 2>/dev/null; then
  dd if="$FB" of="$OUT" bs="$BYTES" count=1 2>/dev/null || {
    echo "failed to read $FB" >&2
    exit 1
  }
fi
chmod a+r "$OUT"
echo "wrote $OUT ($(wc -c <"$OUT") bytes)"

# Optional: X11 grab when scrot works (not relied on for PS4 I/O errors)
AUTH=$(ls -t /tmp/serverauth.* 2>/dev/null | head -1)
if [[ -n "$AUTH" ]] && command -v scrot &>/dev/null; then
  runuser -u psxita -- env DISPLAY=:0 XAUTHORITY="$AUTH" scrot -o "$PNG" 2>/dev/null && echo "also $PNG" || true
fi

AUTH=$(ls -t /tmp/serverauth.* 2>/dev/null | head -1)
if [[ -n "$AUTH" ]] && command -v import &>/dev/null; then
  runuser -u psxita -- env DISPLAY=:0 XAUTHORITY="$AUTH" \
    import -window root /tmp/ps4-x11.png 2>/dev/null && echo "also /tmp/ps4-x11.png (X11 root)"
fi

echo "On Mac: scp root@\$PS4:/tmp/ps4-fb.raw tmp/ && python3 tools/ps4-linux-fb-to-png.py tmp/ps4-fb.raw"
echo "If fb0 is black but HDMI shows a desktop, pull /tmp/ps4-x11.png when ImageMagick import works."