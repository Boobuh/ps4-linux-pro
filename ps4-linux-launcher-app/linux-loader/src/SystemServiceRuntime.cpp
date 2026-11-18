// License: GPL-3.0

#include "SystemServiceRuntime.h"

#include <cstring>

#include "AppFileLog.h"

extern "C" int sceSystemServiceReceiveEvent(OrbisSystemServiceEventLite *event);
extern "C" int sceSystemServiceGetStatus(void *status);
extern "C" int sceSystemServicePowerTick(void);
extern "C" uint64_t sceKernelGetProcessTime(void);

namespace {

constexpr int kSystemServiceNoEvent = static_cast<int>(0x80940002u);
constexpr uint32_t kEventOnResume = 0x10000000u;
constexpr uint64_t kTvHomeOverlaySuppressUs = 4ULL * 1000000ULL;

OrbisSystemServiceEventLite g_SystemServiceEvent {};
alignas(16) uint8_t g_SystemServiceStatus[kOrbisSystemServiceStatusBytes];
uint64_t g_OverlaySuppressUntilUs = 0;

void refreshOverlayFromStatus(bool &systemUiOverlayActive) {
  std::memset(g_SystemServiceStatus, 0, sizeof(g_SystemServiceStatus));
  if (sceSystemServiceGetStatus(g_SystemServiceStatus) != 0) {
    return;
  }
  const auto *st = reinterpret_cast<const OrbisSystemServiceStatusLite *>(g_SystemServiceStatus);
  // Homebrew often reports is_in_background_execution=1 while foreground; only block on real system UI.
  systemUiOverlayActive = st->is_system_ui_overlaid != 0;
}

} // namespace

void SystemServiceNoteTvRemoteHomeIgnored() {
  g_OverlaySuppressUntilUs = sceKernelGetProcessTime() + kTvHomeOverlaySuppressUs;
}

void SystemServicePumpFrame(bool &systemUiOverlayActive) {
  const uint64_t now = sceKernelGetProcessTime();
  if (g_OverlaySuppressUntilUs != 0 && now < g_OverlaySuppressUntilUs) {
    systemUiOverlayActive = false;
  } else {
    refreshOverlayFromStatus(systemUiOverlayActive);
  }

  for (int i = 0; i < 16; i++) {
    std::memset(&g_SystemServiceEvent, 0, sizeof(g_SystemServiceEvent));
    const int ret = sceSystemServiceReceiveEvent(&g_SystemServiceEvent);
    if (ret == kSystemServiceNoEvent) {
      break;
    }
    if (ret != 0) {
      break;
    }
    APP_LOG_INFO("SystemService event type=0x%08x", g_SystemServiceEvent.event_type);
    if (g_SystemServiceEvent.event_type == kEventOnResume) {
      systemUiOverlayActive = false;
    }
  }

  (void)sceSystemServicePowerTick();
}
