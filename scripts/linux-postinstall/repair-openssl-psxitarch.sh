#!/bin/bash
# Recover psxitarch after accidental openssl/curl major upgrade (SSH/curl break: libssl.so.1.1).
# Run on the PS4 console as root (local keyboard), not over SSH if sshd is down.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run: sudo bash $0" >&2
  exit 1
fi

CACHE=/var/cache/pacman/pkg
shopt -s nullglob
pkgs=("$CACHE"/openssl-1.1.*.pkg.tar.* "$CACHE"/openssl-1.1.*.pkg.tar.zst)
if ((${#pkgs[@]} == 0)); then
  echo "No openssl-1.1 package in $CACHE — need network or USB with:"
  echo "  https://archive.archlinux.org/packages/openssl/openssl-1.1/"
  echo "Then: pacman -U openssl-1.1.1w-2-x86_64.pkg.tar.zst"
  exit 1
fi

echo "Reinstalling ${pkgs[0]}…"
pacman -U --noconfirm "${pkgs[0]}"

curl_pkgs=("$CACHE"/curl-7.*.pkg.tar.* "$CACHE"/curl-7.*.pkg.tar.zst)
if ((${#curl_pkgs[@]} > 0)); then
  echo "Downgrading curl to ${curl_pkgs[-1]}…"
  pacman -U --noconfirm "${curl_pkgs[-1]}"
fi

systemctl restart sshd 2>/dev/null || rc-service sshd restart 2>/dev/null || true
echo "OK — retry SSH from Mac. Then install Discord with DISCORD_TARBALL=…"