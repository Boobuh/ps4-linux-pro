#!/usr/bin/env python3
"""Optional SELF header patches (legacy). DO NOT patch @0x0C: those bytes are HeaderSize/MetaSize, not a magic dword.

Unified PS4 Linux (10 SELF entries) must keep create-fself values 0x440 / 0x470 (LE u32 0x04700440).
Copying Apollo 0x3D0/0x3D0 (8 entries) corrupts the SELF and causes CE-41839-5 with empty logs.
Default ship path: PS4LINUX_FSELF_PATCH_PROFILE=none (no patches).
"""
import sys
import os

# Offsets verified against tmp/console-evidence/ex-apollo/uroot/eboot.bin
# Profile: apollo (same console as Apollo homebrew) or onefamily.
PATCHES_APOLLO: list[tuple[int, bytes, str]] = [
    (0x0C, bytes.fromhex("d003d003"), "SELF type/version dword"),
    (0x70, bytes.fromhex("00010000"), "header field @0x70 (Apollo LE u32 0x100)"),
    (0x78, bytes.fromhex("00010000"), "header field @0x78"),
]

PATCHES_ONEFAMILY: list[tuple[int, bytes, str]] = [
    (0x0C, bytes.fromhex("d003d003"), "SELF type/version dword"),
    (0x70, bytes.fromhex("60000000"), "header field @0x70 (OneFamily LE u32 0x60)"),
    (0x78, bytes.fromhex("60000000"), "header field @0x78"),
]


PATCHES_MINIMAL: list[tuple[int, bytes, str]] = [
    (0x0C, bytes.fromhex("d003d003"), "SELF type/version dword"),
]

# Safe with 10-entry unified SELF: only SelfEntry property dwords (does not touch HeaderSize/MetaSize @0x0C).
PATCHES_ENTRIES: list[tuple[int, bytes, str]] = [
    (0x70, bytes.fromhex("00010000"), "SelfEntry properties @0x70 (Apollo LE u32 0x100)"),
    (0x78, bytes.fromhex("00010000"), "SelfEntry properties @0x78"),
]

# Hardware (GoldHEN): create-fself-macos leaves @0x70=0x80 on 10-entry unified links → CE-41839 before BootTrace.
# Thin 8-entry builds already match OneFamily @0x70=0x60 — patch unified links to the same (does not touch @0x0C).
PATCHES_ONEFAMILY_ENTRIES: list[tuple[int, bytes, str]] = [
    (0x70, bytes.fromhex("60000000"), "SelfEntry properties @0x70 (OneFamily LE u32 0x60)"),
    (0x78, bytes.fromhex("60000000"), "SelfEntry properties @0x78"),
]


def patches_for_profile() -> list[tuple[int, bytes, str]]:
    profile = os.environ.get("PS4LINUX_FSELF_PATCH_PROFILE", "apollo").strip().lower()
    if profile in ("minimal", "0c", "0x0c"):
        return PATCHES_MINIMAL
    if profile in ("onefamily-entries", "of-entries", "onefamily_entries"):
        return PATCHES_ONEFAMILY_ENTRIES
    if profile in ("entries", "entry", "0x70"):
        return PATCHES_ENTRIES
    if profile in ("onefamily", "one", "of"):
        return PATCHES_ONEFAMILY
    if profile in ("none", "raw"):
        return []
    return PATCHES_APOLLO


def main() -> int:
    path = sys.argv[1]
    patch_list = patches_for_profile()
    changed = False
    with open(path, "r+b") as f:
        for off, good, label in patch_list:
            f.seek(off)
            cur = f.read(len(good))
            if cur == good:
                continue
            f.seek(off)
            f.write(good)
            print(f"patched {path} {label} @0x{off:X}: {cur.hex()} -> {good.hex()}")
            changed = True
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
