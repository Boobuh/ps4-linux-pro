// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++, C#, and Java: http://www.viva64.com

// License: GPL-3.0

#include "App.h"

#include <orbis/Sysmodule.h>     // sceSysmoduleLoadModuleInternal
#include <orbis/SystemService.h> // sceSystemServiceLoadExec
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstddef> // NULL

#include "libLog.h"
#include "notifi.h"

#include "AppFileLog.h"
#include "BootTrace.h"
#include "Utility.h" // g_Shellcode and Utility::memoryProtectedDestroy()

extern "C" {
extern int backtrace(void *p_Array, int p_Len);
}

void signalHandler(int p_SignalNum);

// TODO: Add to SDK
static const OrbisSysModuleInternal ORBIS_SYSMODULE_INTERNAL_SYSUTIL = (OrbisSysModuleInternal)0x80000026;
static const OrbisSysModuleInternal ORBIS_SYSMODULE_INTERNAL_libSceGnmDriver = (OrbisSysModuleInternal)0x80000052;

static bool loadRequiredModule(OrbisSysModuleInternal id, const char *label) {
  if (sceSysmoduleLoadModuleInternal(id) != 0) {
    APP_LOG_ERROR("sceSysmoduleLoadModuleInternal failed: %s", label);
    notifi(NULL, "PS4 Linux: module load failed (%s)", label);
    return false;
  }
  return true;
}

void signalHandler(int p_SignalNum) {
  void *s_Array[100];

  logKernel(LL_Error, "signalHandler: signal %d", p_SignalNum);

  switch (p_SignalNum) {
  case SIGSEGV:
    logKernel(LL_Debug, "%s", "SIGSEGV");
    break;
  default:
    break;
  }

  backtrace(s_Array, 100);

  APP_LOG_ERROR("crash signal=%d shellcode=%s", p_SignalNum, g_Shellcode != NULL ? "active" : "none");
  bootTrace("guest: crash signal (see APP log if present)");

  if (g_Shellcode != NULL) {
    Utility::MemoryProtectedDestroy(g_Shellcode);
    g_Shellcode = NULL;
    notifi(NULL, "Linux loader crashed (signal %d). Try PayLoader or a different payload.", p_SignalNum);
  }
}

static void installCrashHandlers(void) {
  struct sigaction action {};
  action.sa_handler = signalHandler;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;

  const int signals[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE};
  for (int sig : signals) {
    sigaction(sig, &action, nullptr);
  }
}

int main() {
  AppFileLog::InitSession();

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE, "SYSTEM_SERVICE")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_VIDEO_OUT, "VIDEO_OUT")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_NET, "NET")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_USER_SERVICE, "USER_SERVICE")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_PAD, "PAD")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_SYSUTIL, "SYSUTIL")) {
    return -1;
  }

  if (!loadRequiredModule(ORBIS_SYSMODULE_INTERNAL_libSceGnmDriver, "libSceGnmDriver")) {
    return -1;
  }

  if (sceSysmoduleLoadModule(ORBIS_SYSMODULE_FREETYPE_OL) < 0) {
    APP_LOG_ERROR("sceSysmoduleLoadModule FREETYPE_OL failed");
    notifi(NULL, "PS4 Linux: FreeType module failed");
    return -1;
  }

  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_NETCTL);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_NET);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_HTTP);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SSL);

  installCrashHandlers();

  Application *s_MainApp = new Application();
  APP_LOG_INFO("Application constructed, entering main loop");
  sceSystemServiceHideSplashScreen();
  s_MainApp->Run();
  delete s_MainApp;

  APP_LOG_INFO("Application main loop ended normally");
  sceSystemServiceLoadExec("exit", NULL);

  return 0;
}
