#pragma once

// Canonical PKG layout — unified eboot only (docs/PS4-HOMEBREW-LOADER-PATTERNS.md)

#define PS4LINUX_EBOOT_MIN_BYTES (512 * 1024)
#define PS4LINUX_MENU_MIN_BYTES PS4LINUX_EBOOT_MIN_BYTES

#define PS4LINUX_MENU_PLAIN_PATH "/app0/assets/boot/guest.oelf"
#define PS4LINUX_MENU_SYNC_PLAIN_PATH "/data/linux/boot/guest.oelf"

#define PS4LINUX_MENU_APP0_PATH "/app0/assets/boot/guest.elf"
#define PS4LINUX_MENU_SYNC_PATH "/data/linux/boot/guest.elf"

#define PS4LINUX_MENU_LEGACY_APP0_LINUX_MENU "/app0/linux_menu.elf"
#define PS4LINUX_MENU_LEGACY_APP0_GUEST "/app0/guest.elf"
#define PS4LINUX_MENU_CACHE_USER "/user/data/guest.elf"
