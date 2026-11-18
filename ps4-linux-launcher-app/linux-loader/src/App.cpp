// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++, C#, and Java: http://www.viva64.com

// License: GPL-3.0

#include "App.h"

#include <orbis/Sysmodule.h>
#include <orbis/SystemService.h>
#include <orbis/libkernel.h>

#include <cstdio>
#include <string>

#include "libLog.h"

#include "AppFileLog.h"
#include "BootTrace.h"
#include "BuildVersion.h"
#include "FailSafe.h"
#include "notifi.h"
#include "Controller.h"
#include "Graphics.h"
#include "Ps4LinuxUiTheme.h"
#include "Language.h"
#if !defined(PS4LINUX_MINIMAL_MENU)
#include "LinuxLoaderView.h"
#endif
#include "Resource.h"
#include "View.h"
#include "SystemServiceRuntime.h"

#include <unistd.h>

// #define SCE_SYSMDOULE_LIBIME 0x0095
// #define SCE_SYSMODULE_IME_DIALOG 0x0096

Application::Application() {
  m_IsRunning = false;
  m_SystemUiOverlay = false;
  bootTraceStep("20a Application ctor start");

  // Initialize system componant
  logKernel(LL_Debug, "%s", "Initialize Language...");
  Lang = new Language();
  bootTrace("app: Language constructed");
  APP_LOG_INFO("Language OK (%s)", Lang->GetName().c_str());
  logKernel(LL_Debug, "%s", "Initialize Graphics...");
  Graph = new Graphics();
  bootTrace("app: Graphics constructed");
  if (!Graph->IsReady()) {
    APP_LOG_ERROR("Graphics init failed (video out / frame buffers)");
    ShowFatalReason("Graphics failed — reboot PS4 and try again.");
  }
  APP_LOG_INFO("Graphics OK %dx%d", Graph->GetScreenWidth(), Graph->GetScreenHeight());
  Graph->FrameBufferFill(PS4LINUX_UI_BG);
  Graph->SwapBuffer(0);
  (void)sceSystemServiceHideSplashScreen();
  bootTraceStep("19b blue framebuffer presented");
  logKernel(LL_Debug, "%s", "Initialize Controller...");
  Ctrl = new Controller();
  APP_LOG_INFO("Controller OK");
  bootTrace("app: Controller constructed");
  logKernel(LL_Debug, "%s", "Initialize Resource...");
  Res = new Resource(this, Lang->GetTypefacePaths());
  if (Graph->IsReady() && !Res->m_Typefaces.empty()) {
    const int h = Graph->GetScreenHeight();
    Color fg = {0xE8, 0xF0, 0xFF, 0xFF};
    Color dim = {0xAA, 0xCC, 0xFF, 0xFF};
    Graph->FrameBufferFill(PS4LINUX_UI_BG);
    Graph->SetFontSize(Res->m_Typefaces, HEADER_FONT_SIZE);
    Graph->DrawText("PS4 Linux", Res->m_Typefaces, BORDER_X, h / 2 - 48, fg, fg);
    Graph->SetFontSize(Res->m_Typefaces, DEFAULT_FONT_SIZE);
    Graph->DrawText("Loading menu…", Res->m_Typefaces, BORDER_X, h / 2 + 8, dim, dim);
    Graph->SwapBuffer(1);
  }
  if (Res->m_Typefaces.empty()) {
    APP_LOG_ERROR("Font load failed — check /app0/assets/fonts/NotoSans-Regular.ttf");
    ShowFatalReason("Font load failed. Reinstall PKG from /data/pkg/PS4-Linux-v*.pkg");
  }
  APP_LOG_INFO("Resource OK");

  // Load some needed module
  // sceSysmoduleLoadModule(SCE_SYSMDOULE_LIBIME);
  // sceSysmoduleLoadModule(SCE_SYSMODULE_IME_DIALOG);

  logKernel(LL_Debug, "%s", "Initialize the Main View...");

#if defined(PS4LINUX_MINIMAL_MENU)
  m_CurrentView = nullptr;
  bootTrace("app: minimal menu (Graphics OK — full loader view next restore stage)");
  APP_LOG_INFO("Minimal menu ready (no LinuxLoaderView yet)");
#else
  LinuxLoaderView *s_MainView = new LinuxLoaderView(this);
  m_CurrentView = s_MainView;
  APP_LOG_INFO("LinuxLoaderView ready");
#endif
}

Application::~Application() {
  // Cleanup
  logKernel(LL_Debug, "%s", "Cleanup Application...");

  delete Lang;
  delete Res;
  delete Graph;
  delete Ctrl;
}

void Application::Update() {
  Ctrl->Update();

  if (m_CurrentView) {
    m_CurrentView->Update();
  } else {
    logKernel(LL_Debug, "%s", "No view setup!");
  }
}

void Application::ShowFatalReason(const std::string &p_Reason) {
  APP_LOG_ERROR("Fatal UI stop: %s", p_Reason.c_str());
  notifi(NULL, "PS4 Linux: %s", p_Reason.c_str());
  sceSystemServiceHideSplashScreen();

  if (Graph == nullptr || !Graph->IsReady()) {
    failSafeGuestStop(p_Reason.c_str());
  }

  while (1) {
    Graph->WaitFlip();

    int s_ScreenHeight = Graph->GetScreenHeight();
    int s_ScreenWidth = Graph->GetScreenWidth();

    Color s_Red = {0xFF, 0x00, 0x00, 0xFF};
    Color s_White = {0xFF, 0xFF, 0xFF, 0xFF};

    Graph->DrawRectangle(0, 0, s_ScreenWidth, s_ScreenHeight, s_Red);

    std::string s_Message = p_Reason + std::string("\n\nClose with PS button.");
    if (Res != nullptr && Lang != nullptr) {
      s_Message = std::string(Lang->Get("errorFatal") + std::string("\n\n") + p_Reason + std::string("\n\n\n\n") +
                              Lang->Get("errorCloseApplication"));
    }

    if (Res != nullptr && !Res->m_Typefaces.empty()) {
      FontSize s_MessageSize;
      Graph->SetFontSize(Res->m_Typefaces, 45);
      Graph->GetTextSize(s_Message, Res->m_Typefaces, &s_MessageSize);
      Graph->DrawText(s_Message, Res->m_Typefaces, ((s_ScreenWidth / 2) - (s_MessageSize.width / 2)),
                      ((s_ScreenHeight / 2) - (s_MessageSize.height / 2)), s_White, s_White);
      Graph->SetFontSize(Res->m_Typefaces, DEFAULT_FONT_SIZE);
    }

    Graph->SwapBuffer(m_FlipArgs);
    m_FlipArgs++;
  }
}

void Application::Render() {
  if (m_FlipArgs == 0) {
    bootTraceStep("21a render begin");
  }
  const int64_t waitFlip = m_FlipArgs > 0 ? static_cast<int64_t>(m_FlipArgs - 1) : -1;
  Graph->WaitFlip(waitFlip);
  if (m_FlipArgs == 0) {
    bootTraceStep("21b after wait/clear");
  }

  if (m_CurrentView) {
    m_CurrentView->Render();
  } else if (Graph != nullptr && Graph->IsReady()) {
#if defined(PS4LINUX_MINIMAL_MENU)
    Color bg = PS4LINUX_UI_BG;
    Graph->FrameBufferFill(bg);
    if (Res != nullptr && !Res->m_Typefaces.empty()) {
      const int w = Graph->GetScreenWidth();
      const int h = Graph->GetScreenHeight();
      Color fg = {0xE0, 0xE8, 0xFF, 0xFF};
      const std::string title = std::string("PS4 Linux v") + PS4_LINUX_PKG_VERSION;
      const std::string sub = "UI restore in progress — modules OK";
      Graph->SetFontSize(Res->m_Typefaces, 52);
      FontSize ts;
      Graph->GetTextSize(title, Res->m_Typefaces, &ts);
      Graph->DrawText(title, Res->m_Typefaces, (w - ts.width) / 2, h / 2 - 40, fg, fg);
      Graph->SetFontSize(Res->m_Typefaces, 28);
      Graph->GetTextSize(sub, Res->m_Typefaces, &ts);
      Graph->DrawText(sub, Res->m_Typefaces, (w - ts.width) / 2, h / 2 + 30, fg, fg);
      Graph->SetFontSize(Res->m_Typefaces, DEFAULT_FONT_SIZE);
    }
#else
    logKernel(LL_Debug, "%s", "No view setup!");
#endif
  } else {
    logKernel(LL_Debug, "%s", "No view setup!");
  }

  if (m_FlipArgs == 0) {
    bootTraceStep("21c before swap");
  }
  Graph->SwapBuffer(m_FlipArgs);
  if (m_FlipArgs == 0) {
    bootTraceStep("21d after swap");
  }
  m_FlipArgs++;
}

void Application::ChangeView(View *p_View) {
  logKernel(LL_Debug, "Change view to %p!", (void *)p_View);

  if (!p_View) {
    return;
  }

  m_CurrentView = p_View;
}

void Application::Run() {
  logKernel(LL_Debug, "%s", "Application: RUN");

  m_FlipArgs = 0;
  m_IsRunning = true;
  bool firstFramePresented = false;

  // Main Loop
  while (m_IsRunning) {
    SystemServicePumpFrame(m_SystemUiOverlay);
    Update();
    Render();
    if (!firstFramePresented) {
      firstFramePresented = true;
      bootTraceStep("22 first frame presented");
      APP_LOG_INFO("First frame presented (minimal menu visible)");
    } else if (m_FlipArgs == 2) {
      bootTraceStep("23 text frame presented");
      APP_LOG_INFO("Minimal menu text drawn");
    }

    if (m_SystemUiOverlay) {
      sceKernelUsleep(16000);
    }
  }
}
