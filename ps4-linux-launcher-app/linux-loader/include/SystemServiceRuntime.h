// License: GPL-3.0

#ifndef SYSTEM_SERVICE_RUNTIME_H
#define SYSTEM_SERVICE_RUNTIME_H

#include <cstddef>
#include <cstdint>

// Sony writes more than a few bytes — use a full buffer (see SystemServiceRuntime.cpp).
constexpr std::size_t kOrbisSystemServiceStatusBytes = 512U;

struct OrbisSystemServiceStatusLite {
  int32_t event_num;
  uint8_t is_system_ui_overlaid;
  uint8_t is_in_background_execution;
  uint8_t is_cpu_mode7_cpu_normal;
  uint8_t is_game_live_streaming_on_air;
  uint8_t is_out_of_vr_play_area;
};

struct OrbisSystemServiceEventLite {
  uint32_t event_type;
  uint8_t param[8192];
};

void SystemServicePumpFrame(bool &systemUiOverlayActive);

/// Bravia Home sets overlay flags; ignore overlay for menu briefly after we discard Home.
void SystemServiceNoteTvRemoteHomeIgnored();

#endif
