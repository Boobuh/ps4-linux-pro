#!/bin/bash
# PS4 psxitarch: black screen but SSH works (or run after reboot). Root only.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

systemctl disable ps4-ubuntu-gui-install.service 2>/dev/null || true
systemctl stop ps4-ubuntu-gui-install.service 2>/dev/null || true
rm -f /var/lib/pacman/db.lck
pkill -9 pacman 2>/dev/null || true
pkill -9 gpg 2>/dev/null || true

# Restore JWM startx if XFCE install was mid-flight
if [[ -f /home/psxita/.xinitrc.jwm-backup ]]; then
  cp -a /home/psxita/.xinitrc.jwm-backup /home/psxita/.xinitrc
  chown psxita:psxita /home/psxita/.xinitrc
fi

ln -sf /home/psxita/.jwmrc-en_US /home/psxita/.jwmrc 2>/dev/null || true
chown -h psxita:psxita /home/psxita/.jwmrc 2>/dev/null || true

pkill -u psxita Xorg 2>/dev/null || true
sleep 2
systemctl restart getty@tty1.service
sleep 4
AUTH=$(ls -t /tmp/serverauth.* 2>/dev/null | head -1)
if [[ -n "$AUTH" ]]; then
  runuser -u psxita -- env DISPLAY=:0 XAUTHORITY="$AUTH" XDG_RUNTIME_DIR=/run/user/1000 \
    pcmanfm --desktop &
fi
echo "OK — JWM should be back on HDMI. Ubuntu on-boot install is DISABLED."