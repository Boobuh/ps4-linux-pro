// License: GPL-3.0

#include "FailSafe.h"

#include <unistd.h>

#include "BootTrace.h"

void failSafeGuestStop(const char *reason) {
  if (reason != NULL) {
    failSafeNotify("PS4 Linux: %s (see FTP log)", reason);
  }
  bootTrace("app: fail-safe hold 20s before exit");
  for (int i = 0; i < 40; i++) {
    usleep(500000);
  }
  _exit(-1);
}
