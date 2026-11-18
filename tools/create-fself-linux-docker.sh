#!/usr/bin/env bash
# Run OpenOrbis bin/linux/create-fself (x86_64) via Docker on macOS — Apollo-matching SELF headers vs create-fself-macos.
set -euo pipefail

if [[ -z "${OO_PS4_TOOLCHAIN:-}" ]]; then
  echo "create-fself-linux-docker.sh: OO_PS4_TOOLCHAIN is not set" >&2
  exit 1
fi

toolchain="$(cd "$OO_PS4_TOOLCHAIN" && pwd)"
fself="$toolchain/bin/linux/create-fself"
if [[ ! -x "$fself" ]]; then
  echo "create-fself-linux-docker.sh: missing $fself" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "create-fself-linux-docker.sh: docker not found" >&2
  exit 1
fi

work="$(pwd)"
exec docker run --rm --platform linux/amd64 \
  -e OO_PS4_TOOLCHAIN=/oo \
  -v "$toolchain:/oo:ro" \
  -v "$work:/work" \
  -w /work \
  debian:bookworm-slim \
  /oo/bin/linux/create-fself "$@"
