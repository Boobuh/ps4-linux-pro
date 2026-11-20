#!/bin/bash
# PS4 psxitarch: keep HDMI on (no DPMS, blank, suspend). Run as root.
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

USER_NAME="${1:-psxita}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"

mkdir -p /etc/systemd/logind.conf.d /etc/systemd/sleep.conf.d /etc/sysctl.d

cat >/etc/systemd/logind.conf.d/ps4-display-stay-on.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
IdleActionSec=0
EOF

cat >/etc/systemd/sleep.conf.d/ps4-no-sleep.conf <<'EOF'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
echo 'kernel.consoleblank = 0' >/etc/sysctl.d/99-ps4-consoleblank.conf
sysctl -p /etc/sysctl.d/99-ps4-consoleblank.conf 2>/dev/null || true

cat >/usr/local/sbin/ps4-display-stay-on.sh <<'EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${XAUTHORITY:-}" ]]; then
  auth="$(ls -t /tmp/serverauth.* 2>/dev/null | head -1 || true)"
  [[ -n "$auth" ]] && export XAUTHORITY="$auth"
fi
command -v xset >/dev/null || exit 0
xset s off
xset s noblank
xset -dpms
xset dpms 0 0 0
EOF
chmod 755 /usr/local/sbin/ps4-display-stay-on.sh

for jwm in "$HOME_DIR"/.jwmrc "$HOME_DIR"/.jwmrc-*; do
  [[ -f "$jwm" ]] || continue
  grep -q ps4-display-stay-on.sh "$jwm" && continue
  sed -i '/<StartupCommand>/a\       /usr/local/sbin/ps4-display-stay-on.sh \&' "$jwm"
done
chown "$USER_NAME:$USER_NAME" "$HOME_DIR"/.jwmrc* 2>/dev/null || true

systemctl disable ps4-ubuntu-gui-install.service 2>/dev/null || true
rm -f /etc/systemd/system/ps4-ubuntu-gui-install.service

systemctl daemon-reload
systemctl restart systemd-logind 2>/dev/null || true

echo "OK — display stay-on applied; JWM runs xset on login."