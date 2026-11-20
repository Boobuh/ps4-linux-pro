#!/bin/bash
# Repair psxita home ownership/perms after root-driven tweaks (skip known-bad corrupt dirs).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo root only >&2; exit 1; }

U=psxita
HOME_DIR=/home/$U
SKIP_REGEX='google-chrome|\.cache/google-chrome'

echo "=== fix-psxita-permissions-ps4 ==="

if ! id "$U" &>/dev/null; then
  echo "user $U missing" >&2
  exit 1
fi

find "$HOME_DIR" ! -path '*google-chrome*' ! -path '*OptGuide*' ! -path '*Dictionaries*' \
  -user root 2>/dev/null | while read -r p; do chown "$U:$U" "$p" 2>/dev/null || true; done
find "$HOME_DIR" ! -user "$U" ! -path '*google-chrome*' 2>/dev/null \
  | while read -r p; do chown "$U:$U" "$p" 2>/dev/null || true; done

for dir in "$HOME_DIR" "$HOME_DIR/.config" "$HOME_DIR/.local" "$HOME_DIR/Applications" "$HOME_DIR/wallpapers"; do
  [[ -d "$dir" ]] && chmod 755 "$dir" 2>/dev/null || true
done
for sec in .ssh .gnupg .config/google-chrome; do
  [[ -d "$HOME_DIR/$sec" ]] && chmod 700 "$HOME_DIR/$sec" 2>/dev/null || true
done

chmod 644 "$HOME_DIR"/.jwmrc-* 2>/dev/null || true
chmod 644 "$HOME_DIR"/.jwmrc-en_US 2>/dev/null || true
chmod +x "$HOME_DIR/.xinitrc" 2>/dev/null || true
chown -h "$U:$U" "$HOME_DIR/.jwmrc" 2>/dev/null || true
chown "$U:$U" "$HOME_DIR/.jwmrc-"* "$HOME_DIR/.xinitrc" 2>/dev/null || true

mkdir -p "$HOME_DIR/wallpapers" /usr/share/backgrounds/ubuntu
chmod 755 "$HOME_DIR/wallpapers" /usr/share/backgrounds/ubuntu
chown "$U:$U" "$HOME_DIR/wallpapers" 2>/dev/null || true

echo "done — verify: ls -la $HOME_DIR/.jwmrc $HOME_DIR/wallpapers"