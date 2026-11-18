#include "BootTrace.h"

#include <orbis/Sysmodule.h>
#include <orbis/SystemService.h>
#include <unistd.h>

int main(void) {
  bootTrace("eboot: thin CSTP00003 shell (probe path verified on hardware)");
  bootTraceStep("00 thin main entered");

  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE) == 0) {
    (void)sceSystemServiceHideSplashScreen();
    bootTraceStep("01 splash hidden (thin shell)");
  } else {
    bootTrace("app: SYSTEM_SERVICE load failed — splash may stick");
  }

  bootTrace("app: thin shell running — incrementally restore full UI after launch OK");

  for (;;) {
    sleep(5);
  }
  return 0;
}
