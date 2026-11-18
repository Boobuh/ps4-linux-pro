#!/usr/bin/env bash
# Produce eboot.bin: create-fself + optional header patch; large links fall back to 8-entry python FSELF when macOS emits 10 entries.
set -euo pipefail

in_elf=""
out_bin=""
paid=""
authinfo=""
toolchain="${OO_PS4_TOOLCHAIN:?}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
patch_py="$repo/tools/ps4-linux-patch-fself-header.py"
make_fself_py="$repo/tools/ps4-linux-make-fself.py"
docker_wrap="$repo/tools/create-fself-linux-docker.sh"
macos_fself="$toolchain/bin/macos/create-fself-macos"
stamp_name=".ps4-linux-fself-method"
# SELF @0x18 program flags: 8 entries (hardware OK) vs 10 (CE-41839 on GoldHEN for this title).
SELF_U18_EIGHT_ENTRY=$((0x00220008))
SELF_U18_TEN_ENTRY=$((0x0022000a))

while [[ $# -gt 0 ]]; do
  case "$1" in
    -in=*) in_elf="${1#-in=}" ;;
    -out=*) ;;
    --eboot) shift; out_bin="${1:?}" ;;
    --paid) shift; paid="${1:?}" ;;
    --authinfo=*) authinfo="${1#--authinfo=}" ;;
    --authinfo) shift; authinfo="${1:?}" ;;
    *) echo "ps4-linux-fself.sh: unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$in_elf" && -n "$out_bin" && -n "$paid" && -n "$authinfo" ]] || {
  echo "ps4-linux-fself.sh: need -in=ELF --eboot OUT --paid ID --authinfo=HEX" >&2
  exit 2
}

write_stamp() {
  local method="$1"
  local dir
  dir="$(cd "$(dirname "$out_bin")" && pwd)"
  printf '%s\n' "$method" >"${dir}/${stamp_name}"
}

run_create_fself() {
  local tool="$1"
  local ptype="${PS4LINUX_FSELF_PTYPE:-fake}"
  local -a cmd=(
    "$tool"
    -in="$in_elf"
    -out="${out_bin}.oelf"
    --eboot "$out_bin"
    --paid "$paid"
    --authinfo="$authinfo"
  )
  if [[ -n "$ptype" ]]; then
    cmd+=(-ptype "$ptype")
  fi
  if [[ -n "${PS4LINUX_FSELF_SDKVER:-}" ]]; then
    cmd+=(-sdkver "$PS4LINUX_FSELF_SDKVER")
  fi
  "${cmd[@]}"
}

read_self_u18() {
  python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(); print(struct.unpack_from('<I',d,0x18)[0])" "$out_bin"
}

run_python_eight_entry_fself() {
  local ptype="${PS4LINUX_FSELF_PTYPE:-fake}"
  python3 "$make_fself_py" "$in_elf" "$out_bin" --paid "$paid" --auth-info "$authinfo" --ptype "$ptype"
  export PS4LINUX_FSELF_PATCH_PROFILE=onefamily-entries
  python3 "$patch_py" "$out_bin"
}

maybe_eight_entry_fallback() {
  local elf_bytes="${1:-0}"
  [[ "$elf_bytes" -lt 200000 ]] && return 1
  # Default off: 8-entry python FSELF (~1.48 MiB) → CE-41839 on GoldHEN (hardware 2026-11-05).
  [[ "${PS4LINUX_FSELF_PYTHON_FALLBACK:-}" != "1" ]] && return 1
  [[ "${PS4LINUX_FSELF_NO_PYTHON_FALLBACK:-}" == "1" ]] && return 1
  local u18
  u18=$(read_self_u18)
  [[ "$u18" -eq "$SELF_U18_TEN_ENTRY" ]] || return 1
  echo "ps4-linux-fself.sh: create-fself emitted 10-entry SELF — rebuilding 8-entry (ps4-linux-make-fself.py)" >&2
  run_python_eight_entry_fself
  write_stamp "eight-entry-fself-fallback"
  echo "ps4-linux-fself.sh: eight-entry-fself-fallback ptype=${PS4LINUX_FSELF_PTYPE:-fake} patch=onefamily-entries" >&2
  return 0
}

finish() {
  local method="$1"
  # Unified menu links: macOS create-fself often emits SELF @0x70=0x80 (kernel reject on hardware).
  # Thin shells keep OneFamily-like 0x60 without patching. Override with PS4LINUX_FSELF_PATCH_PROFILE.
  if [[ -z "${PS4LINUX_FSELF_PATCH_PROFILE:-}" ]]; then
    local elf_bytes=0
    if [[ -f "$in_elf" ]]; then
      elf_bytes=$(stat -f%z "$in_elf" 2>/dev/null || stat -c%s "$in_elf" 2>/dev/null || echo 0)
    fi
    if [[ "$elf_bytes" -lt 200000 ]]; then
      export PS4LINUX_FSELF_PATCH_PROFILE=none
    else
      # Match OpenOrbis hello_world (~1.2 MiB, 10-entry, @0x70=0x80) — do not force OneFamily @0x60 on large links.
      export PS4LINUX_FSELF_PATCH_PROFILE=none
    fi
  fi
  if [[ "$PS4LINUX_FSELF_PATCH_PROFILE" != "none" && "$PS4LINUX_FSELF_PATCH_PROFILE" != "raw" ]]; then
    python3 "$patch_py" "$out_bin"
  fi
  write_stamp "$method"
  echo "ps4-linux-fself.sh: ${method} ptype=${PS4LINUX_FSELF_PTYPE:-fake} patch=${PS4LINUX_FSELF_PATCH_PROFILE}" >&2
}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ptype="${PS4LINUX_FSELF_PTYPE:-fake}"
  docker_args=(
    "$docker_wrap"
    -in="$in_elf" -out="${out_bin}.oelf" --eboot "$out_bin"
    --paid "$paid" --authinfo="$authinfo"
  )
  [[ -n "$ptype" ]] && docker_args+=(-ptype "$ptype")
  [[ -n "${PS4LINUX_FSELF_SDKVER:-}" ]] && docker_args+=(-sdkver "$PS4LINUX_FSELF_SDKVER")
  if OO_PS4_TOOLCHAIN="$toolchain" "${docker_args[@]}"; then
    elf_bytes=$(stat -f%z "$in_elf" 2>/dev/null || stat -c%s "$in_elf" 2>/dev/null || echo 0)
    if maybe_eight_entry_fallback "$elf_bytes"; then
      exit 0
    fi
    finish "linux/create-fself"
    exit 0
  fi
fi

echo "ps4-linux-fself.sh: Docker unavailable — create-fself-macos" >&2
run_create_fself "$macos_fself"
elf_bytes=$(stat -f%z "$in_elf" 2>/dev/null || stat -c%s "$in_elf" 2>/dev/null || echo 0)
if maybe_eight_entry_fallback "$elf_bytes"; then
  exit 0
fi
finish "macos/create-fself-macos"
