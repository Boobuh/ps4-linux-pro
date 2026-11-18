// License: GPL-3.0
// Shared PS4 pad bit helpers (OpenOrbis + SCE docs).

#ifndef PS4LINUX_PAD_INPUT_COMMON_H
#define PS4LINUX_PAD_INPUT_COMMON_H

#include <orbis/_types/pad.h>

#ifndef ORBIS_PAD_PORT_TYPE_REMOTE_CONTROL
#define ORBIS_PAD_PORT_TYPE_REMOTE_CONTROL 16
#endif

#ifndef ORBIS_PAD_BUTTON_PLAYSTATION
#define ORBIS_PAD_BUTTON_PLAYSTATION 0x00010000u
#endif

#ifndef ORBIS_PAD_BUTTON_INTERCEPTED
#define ORBIS_PAD_BUTTON_INTERCEPTED 0x80000000u
#endif

/// Shell sets this when routing input; real buttons are the lower bits (often Cross for CEC OK).
inline unsigned int ps4linuxNormalizePadButtons(unsigned int raw) {
  return raw & ~ORBIS_PAD_BUTTON_INTERCEPTED;
}

inline bool ps4linuxIsInterceptedOnly(unsigned int raw) {
  return raw == ORBIS_PAD_BUTTON_INTERCEPTED;
}

inline bool ps4linuxIsTvRemoteHomeRaw(unsigned int raw) {
  if (ps4linuxIsInterceptedOnly(raw)) {
    return true;
  }
  const unsigned int stripped = ps4linuxNormalizePadButtons(raw);
  return (stripped & ORBIS_PAD_BUTTON_PLAYSTATION) != 0;
}

#endif
