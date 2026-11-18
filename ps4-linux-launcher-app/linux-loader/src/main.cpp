// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++, C#, and Java: http://www.viva64.com

// License: GPL-3.0

#if !defined(PS4LINUX_STOP_BEFORE_APPLICATION)
#include "App.h"
#endif

#include <orbis/Sysmodule.h>
#include <orbis/_types/sysmodule.h>
#include <orbis/SystemService.h>
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>

#include <clocale>
#include <cstddef>
#include <cstdio>

#include "libLog.h"
#include "notifi.h"

#include "AppEntry.h"
#include "AppFileLog.h"
#include "BootTrace.h"
#include "FailSafe.h"
#if !defined(PS4LINUX_STOP_BEFORE_APPLICATION)
#include "Utility.h"
#endif

extern "C" {
extern int backtrace(void *p_Array, int p_Len);
}

static const OrbisSysModuleInternal ORBIS_SYSMODULE_INTERNAL_SYSUTIL = (OrbisSysModuleInternal)0x80000026;
static const OrbisSysModuleInternal ORBIS_SYSMODULE_INTERNAL_libSceGnmDriver = (OrbisSysModuleInternal)0x80000052;

void signalHandler(int p_SignalNum);

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

#if !defined(PS4LINUX_STOP_BEFORE_APPLICATION)
  if (g_Shellcode != NULL) {
    Utility::MemoryProtectedDestroy(g_Shellcode);
    g_Shellcode = NULL;
    notifi(NULL, "Linux loader crashed (signal %d). Try PayLoader or a different payload.", p_SignalNum);
  } else
#endif
  {
    char crashLine[128];
    (void)snprintf(crashLine, sizeof(crashLine), "guest: crash signal %d during run", p_SignalNum);
    bootTrace(crashLine);
    notifi(NULL, "PS4 Linux crashed during startup (signal %d). Reboot and retry.", p_SignalNum);
  }
}

extern "C" int ps4_linux_app_main(void) {
  bootTraceStep("10 ps4_linux_app_main entered");
  bootTrace("app: guest main entered");
  AppFileLog::InitSession();
  (void)setlocale(LC_ALL, "en_US.UTF-8");

  bootTraceStep("11 SYSTEM_SERVICE");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE) != 0) {
    APP_LOG_ERROR("SYSTEM_SERVICE module load failed");
    failSafeGuestStop("SYSTEM_SERVICE module failed");
  }
  (void)sceSystemServiceHideSplashScreen();
  bootTraceStep("11b splash hidden (post SYSTEM_SERVICE)");

  bootTraceStep("12 VIDEO_OUT");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_VIDEO_OUT) != 0) {
    APP_LOG_ERROR("VIDEO_OUT module load failed");
    failSafeGuestStop("VIDEO_OUT module failed");
  }

  bootTraceStep("13 NET");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_NET) != 0) {
    APP_LOG_ERROR("NET module load failed");
    failSafeGuestStop("NET module failed");
  }

  bootTraceStep("14 USER_SERVICE");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_USER_SERVICE) != 0) {
    APP_LOG_ERROR("USER_SERVICE module load failed");
    failSafeGuestStop("USER_SERVICE module failed");
  }

  bootTraceStep("15 PAD");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_PAD) != 0) {
    APP_LOG_ERROR("PAD module load failed");
    failSafeGuestStop("PAD module failed");
  }

  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_KEYBOARD);
  sceSysmoduleLoadModule(ORBIS_SYSMODULE_KEYBOARD);

  bootTraceStep("16 SYSUTIL");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SYSUTIL) != 0) {
    APP_LOG_ERROR("SYSUTIL module load failed");
    failSafeGuestStop("SYSUTIL module failed");
  }

  bootTraceStep("17 GNM");
  if (sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_libSceGnmDriver) != 0) {
    APP_LOG_ERROR("libSceGnmDriver module load failed");
    failSafeGuestStop("GNM driver module failed");
  }

  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_NETCTL);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_NET);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_HTTP);
  sceSysmoduleLoadModuleInternal(ORBIS_SYSMODULE_INTERNAL_SSL);

  bootTraceStep("18 FREETYPE");
  if (sceSysmoduleLoadModule(ORBIS_SYSMODULE_FREETYPE_OL) < 0) {
    APP_LOG_ERROR("FREETYPE_OL module load failed");
    failSafeGuestStop("FreeType module failed");
  }

  struct sigaction action {};
  action.sa_handler = signalHandler;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;

  const int crashSignals[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE};
  for (int sig : crashSignals) {
    sigaction(sig, &action, nullptr);
  }

  bootTrace("app: modules OK, constructing Application");
  APP_LOG_INFO("Core modules loaded");
  bootTraceStep("19 before Application (splash until first frame)");

#if defined(PS4LINUX_STOP_BEFORE_APPLICATION)
  bootTraceStep("19 hide splash before Application");
  sceSystemServiceHideSplashScreen();
  bootTrace("app: module probe OK — halted before Application (UI restore bisect)");
  APP_LOG_INFO("Restore stage: modules loaded, no UI ctor");
  for (;;) {
    sleep(5);
  }
#else
  bootTraceStep("20 Application ctor");
  Application *s_MainApp = new Application();
  bootTraceStep("21 Application Run loop");
  APP_LOG_INFO("Application constructed, entering main loop");
  s_MainApp->Run();
  delete s_MainApp;

  APP_LOG_INFO("Application main loop ended normally");
  sceSystemServiceLoadExec("exit", NULL);
#endif

  return 0;
}

int main(void) {
  logSetLogLevel(LL_All);
  bootTrace("eboot: unified OpenOrbis eboot (kernel loader)");
  bootTraceStep("00 main entered");
  return ps4_linux_app_main();
}
