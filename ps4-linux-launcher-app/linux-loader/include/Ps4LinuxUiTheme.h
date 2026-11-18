#ifndef PS4_LINUX_UI_THEME_H
#define PS4_LINUX_UI_THEME_H

#include "Graphics.h"

// App chrome — Sony-style blue (not near-black).
inline constexpr Color PS4LINUX_UI_BG = {0x0A, 0x3D, 0x8C, 0xFF};
inline constexpr Color PS4LINUX_UI_BG_PANEL = {0x06, 0x2A, 0x66, 0xFF};

// TV overscan safe margin (~5% of 1920) — menu uses this instead of raw BORDER_X where noted.
inline constexpr int PS4LINUX_SAFE_X = 128;
inline constexpr int PS4LINUX_CONTENT_MAX_W = 1664;

// Menu rows / hint chips (TV-safe touch targets).
inline constexpr int PS4LINUX_MENU_PAD_X = 28;
inline constexpr int PS4LINUX_MENU_PAD_Y = 14;
inline constexpr int PS4LINUX_MENU_ROW_H = 52;
inline constexpr int PS4LINUX_MENU_ROW_GAP = 10;
inline constexpr int PS4LINUX_HINT_ROW_H = 40;
inline constexpr int PS4LINUX_HINT_PAD_Y = 11;

inline constexpr Color PS4LINUX_MENU_ROW_HI = {0x28, 0x58, 0x88, 0xFF};
inline constexpr Color PS4LINUX_MENU_ROW_LO = {0x10, 0x32, 0x72, 0xFF};
inline constexpr Color PS4LINUX_HINT_ROW_BG = {0x0C, 0x28, 0x5C, 0xFF};

#endif