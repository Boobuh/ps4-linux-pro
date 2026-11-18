#!/bin/bash
# One-time: let your Mac SSH in without passwords (key in authorized_keys).
# Usage on PS4 Linux:  curl -fsSL "http://<mac-ip>:8766/enable-mac-control.sh" | sudo bash -s -- "http://<mac-ip>:8766/ps4-linux.pub"
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo." >&2
  exit 1
fi

PUB_URL="${1:-}"
if [[ -z "$PUB_URL" ]]; then
  echo "Need pubkey URL, e.g.: $0 http://10.0.1.13:8766/ps4-linux.pub" >&2
  exit 1
fi

install -d -m 700 /root/.ssh
TMP="$(mktemp)"
curl -fsSL "$PUB_URL" >"$TMP"
grep -v '^[[:space:]]*$' "$TMP" >>/root/.ssh/authorized_keys || true
rm -f "$TMP"
sort -u -o /root/.ssh/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

systemctl enable sshd 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true
systemctl start sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# Optional drops for scripts dropped from GoldHEN FTP on next PS4 boot (Linux may mount ps4 paths later).
install -d -m 755 /data/linux/boot 2>/dev/null || true

echo "OK — Mac can use:  ssh -i ~/.ssh/ps4_linux_ed25519 root@$(hostname -I 2>/dev/null | awk '{print $1}')"