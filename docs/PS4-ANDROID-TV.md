# Android TV (moved)

Android TV / Baikal PKG work is **not** part of `ps4-linux-pro` anymore.

Use **[Boobuh/ps4-android-tv-pro](https://github.com/Boobuh/ps4-android-tv-pro)** (fork of [odiecay/android-tv-ps4](https://github.com/odiecay/android-tv-ps4)) for:

- crashniels 6.15 Baikal kernel + v60 HDMI patches
- `Android-TV-for-PS4.pkg` build and upload
- `tools/ps4-android-tv-console.swift` log pull

This repo stays focused on **PS4 Linux / psxitarch** (loader, neocine kernel, `/data/linux/boot/`).

## Errors you might still see here

### `fatal: detected dubious ownership`

The tree lives under `/Users/Shared/`. Use the repo git wrapper (no global `git config` required):

```bash
export PATH="/Users/Shared/dev/ps4-linux-pro/tools/bin:$PATH"
git status
```

Or once per machine (your choice):  
`git config --global --add safe.directory /Users/Shared/dev/ps4-linux-pro`

### `AssertionError: PS4_13_52` in `tmp/android-tv-release-build2.log`

That log is from the **old** layout (`/work/vendor/android-tv-ps4/...`). Android TV builds must run from **`ps4-android-tv-pro`**:

```bash
cd /Users/Shared/dev/ps4-android-tv-pro
bash scripts/android-tv-link-linux-pro-shared.sh   # OpenOrbis + build cache
bash scripts/macos-docker-ubuntu-build-image.sh
bash scripts/android-tv-build-live.sh release
```

New logs: `ps4-android-tv-pro/tmp/android-tv-release-build.log`. The 13.52 kexec pin mismatch is a **warning** on fork builds unless `ATV_KEXEC_STRICT_CONFIRMED=1`.