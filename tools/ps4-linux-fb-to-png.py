#!/usr/bin/env python3
"""Convert ps4-hdmi-screenshot.sh fb0 raw dump to PNG (default BGRA)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser(description="PS4 Linux fb0 raw -> PNG")
    parser.add_argument("raw", type=Path, help="e.g. tmp/ps4-fb.raw from console")
    parser.add_argument("-o", "--output", type=Path, default=None)
    parser.add_argument("-w", "--width", type=int, default=1920)
    parser.add_argument("-H", "--height", type=int, default=1080)
    parser.add_argument(
        "--mode",
        choices=("BGRA", "RGBA", "BGRX"),
        default="BGRA",
        help="pixel order (try BGRA first for PS4 amdgpu fb)",
    )
    args = parser.parse_args()
    data = args.raw.read_bytes()
    need = args.width * args.height * 4
    if len(data) < need:
        print(f"raw too small: {len(data)} < {need}", file=sys.stderr)
        return 1
    out = args.output or args.raw.with_suffix(".png")
    img = Image.frombytes("RGBA", (args.width, args.height), data[:need], "raw", args.mode)
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())