// License: GPL-3.0

#include <fcntl.h>
#include <orbis/Sysmodule.h>
#include <orbis/SystemService.h>
#include <stddef.h>
#include <unistd.h>

#include "BootTrace.h"
#include "libLog.h"
#include "notifi.h"

static const OrbisSysModuleInternal ORBIS_SYSMODULE_INTERNAL_SYSUTIL = (OrbisSysModuleInternal)0x80000026;

// Some mod menus scan for a running "eboot.bin" and attach automatically — guest runs as guest.elf.
int main(void) {
  logSetLogLevel(LL_All);
  bootTrace("eboot: PS4 Linux chain start");

  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE) != 0) {
    bootTrace("eboot: FATAL cannot load SYSTEM_SERVICE");
    logKernel(LL_Fatal, "%s", "Unable to load ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE");
    return -1;
  }

  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSUTIL);

  const char *guestPath = "/app0/guest.elf";
  int fd = open(guestPath, O_RDONLY);
  if (fd < 0) {
    bootTrace("eboot: FATAL cannot open guest.elf (missing from app0?)");
    notifi(NULL, "PS4 Linux: guest.elf missing — reinstall PKG");
    return -1;
  }
  close(fd);
  bootTrace("eboot: guest.elf readable, LoadExec…");

  logKernel(LL_Info, "%s", "Loading \"/app0/guest.elf\"");
  const int loadRet = sceSystemServiceLoadExec(guestPath, NULL);
  bootTrace("eboot: LoadExec returned — guest did not start");
  logKernel(LL_Error, "LoadExec guest.elf returned %d", loadRet);
  notifi(NULL, "PS4 Linux: LoadExec guest failed (%d)", loadRet);

  return -1;
}
