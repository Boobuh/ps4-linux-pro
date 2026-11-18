// License: GPL-3.0
// Tiny PKG eboot (<512 KiB): load plain menu ELF in-process (no LoadExec / no unified eboot).

#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include <orbis/Sysmodule.h>
#include <orbis/SystemService.h>

#include "BootTrace.h"
#include "BuildVersion.h"
#include "GuestPlainLoader.h"
#include "PkgLayout.h"
#include "libLog.h"

static void logEbootOnDiskSize(void) {
  int fd = open("/app0/eboot.bin", O_RDONLY);
  if (fd < 0) {
    bootTraceStep("probe /app0/eboot.bin open failed");
    return;
  }
  const off_t seekSz = lseek(fd, 0, SEEK_END);
  close(fd);
  char line[192];
  (void)snprintf(line, sizeof(line), "eboot: on-disk /app0/eboot.bin seek=%lld (must be <524288)", (long long)seekSz);
  bootTrace(line);
  if (seekSz >= (off_t)(512 * 1024)) {
    bootTrace("eboot: WARN large eboot — CE-41839-5 risk on Package Installer");
  }
}

static const char *kMenuPlainPaths[] = {
    PS4LINUX_MENU_PLAIN_PATH,
    PS4LINUX_MENU_SYNC_PLAIN_PATH,
    NULL,
};

int main(void) {
  logSetLogLevel(LL_All);
  bootTraceStep("00 chain main entered");
  bootTrace("eboot: PS4 Linux chain start (plain ELF loader)");

  char verLine[128];
  (void)snprintf(verLine, sizeof(verLine), "eboot: PKG v%s build %s APP %s", PS4_LINUX_PKG_VERSION, PS4_LINUX_PKG_BUILD,
                 PS4_LINUX_PKG_APP_VER);
  bootTrace(verLine);

  logEbootOnDiskSize();

  bootTraceStep("01 load SYSTEM_SERVICE");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE) == 0) {
    (void)sceSystemServiceHideSplashScreen();
    bootTraceStep("02 splash hidden (early)");
  }

  for (int i = 0; kMenuPlainPaths[i] != NULL; i++) {
    char loadExecLine[192];
    (void)snprintf(loadExecLine, sizeof(loadExecLine), "loader: LoadExec try %s", kMenuPlainPaths[i]);
    bootTrace(loadExecLine);
    const int32_t le = sceSystemServiceLoadExec(kMenuPlainPaths[i], NULL);
    char leRet[128];
    (void)snprintf(leRet, sizeof(leRet), "loader: LoadExec returned %d (plain oelf)", (int)le);
    bootTrace(leRet);

    bootTraceStep("03 guestPlainLoaderRun");
    char tryLine[160];
    (void)snprintf(tryLine, sizeof(tryLine), "loader: try %s", kMenuPlainPaths[i]);
    bootTrace(tryLine);
    const int rc = guestPlainLoaderRun(kMenuPlainPaths[i]);
    char rcLine[128];
    (void)snprintf(rcLine, sizeof(rcLine), "loader: returned %d (unexpected)", rc);
    bootTrace(rcLine);
  }

  bootTrace("eboot: FATAL no menu plain ELF");
  bootTraceStep("99 menu missing");
  for (int i = 0; i < 30; i++) {
    usleep(500000);
  }
  return -1;
}
