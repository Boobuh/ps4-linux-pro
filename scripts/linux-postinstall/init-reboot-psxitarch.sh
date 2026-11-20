#!/bin/bash
# PS4 psxitarch: prep a clean JWM session then reboot. Run as root (SSH or tty).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "sudo -i first" >&2; exit 1; }

systemctl disable ps4-ubuntu-gui-install.service 2>/dev/null || true
systemctl stop ps4-ubuntu-gui-install.service 2>/dev/null || true
rm -f /var/lib/ps4-ubuntu-gui-installed /var/lib/pacman/db.lck
pkill -9 pacman gpg 2>/dev/null || true

printf '%s\n' 'exec /usr/bin/jwm -f /home/psxita/.jwmrc-en_US' >/home/psxita/.xinitrc
chown psxita:psxita /home/psxita/.xinitrc
ln -sf /home/psxita/.jwmrc-en_US /home/psxita/.jwmrc
chown -h psxita:psxita /home/psxita/.jwmrc

# Blueman + polkit at login
if [[ -x /usr/local/sbin/enable-bluetooth-ps4.sh ]]; then
  /usr/local/sbin/enable-bluetooth-ps4.sh psxita || true
fi

sync
echo "Rebooting in 3s (JWM desktop after login)…"
sleep 3
/sbin/reboot