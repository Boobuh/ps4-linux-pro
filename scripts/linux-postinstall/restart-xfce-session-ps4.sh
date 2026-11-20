#!/bin/bash
# Reload HDMI XFCE after xfconf XML changes (panel/themes). Root on console.
# Uses SIGKILL so xfconfd does not write the old panel layout back to disk.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root only" >&2; exit 1; }

DESKTOP_USER="${DESKTOP_USER:-psxita}"

echo "=== restart-xfce-session-ps4: stopping X for $DESKTOP_USER ==="
pkill -9 -u "$DESKTOP_USER" xfce4-panel 2>/dev/null || true
pkill -9 -u "$DESKTOP_USER" xfce4-session 2>/dev/null || true
pkill -9 -u "$DESKTOP_USER" Xorg 2>/dev/null || true
pkill -9 -u "$DESKTOP_USER" startx 2>/dev/null || true
sleep 2
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true

echo "=== restarting getty@tty1 (autologin + startx) ==="
systemctl restart getty@tty1.service
sleep 10

if pgrep -u "$DESKTOP_USER" Xorg >/dev/null; then
  echo "OK: Xorg is up on tty1"
  pgrep -au "$DESKTOP_USER" -f 'whiskermenu|libwhiskermenu' && echo "OK: whisker panel plugin loaded" || \
    echo "warn: whisker not in process list yet — check HDMI in ~15s"
else
  echo "warn: Xorg not running — on PS4 HDMI press Alt+F1 or SSH and run: systemctl restart getty@tty1"
fi