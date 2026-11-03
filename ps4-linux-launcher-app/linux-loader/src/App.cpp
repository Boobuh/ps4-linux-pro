// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++, C#, and Java: http://www.viva64.com

// License: GPL-3.0

#include "App.h"

#include <orbis/Sysmodule.h>
#include <orbis/libkernel.h>

#include <cstdio>
#include <string>

#include "libLog.h"

#include "AppFileLog.h"
#include "notifi.h"
#include "Controller.h"
#include "Graphics.h"
#include "Language.h"
#include "LinuxLoaderView.h"
#include "Resource.h"
#include "View.h"

// #define SCE_SYSMDOULE_LIBIME 0x0095
// #define SCE_SYSMODULE_IME_DIALOG 0x0096

Application::Application() {
  m_IsRunning = false;

  // Initialize system componant
  logKernel(LL_Debug, "%s", "Initialize Language...");
  Lang = new Language();
  APP_LOG_INFO("Language OK (%s)", Lang->GetName().c_str());
  logKernel(LL_Debug, "%s", "Initialize Controller...");
  Ctrl = new Controller();
  APP_LOG_INFO("Controller OK");
  logKernel(LL_Debug, "%s", "Initialize Graphics...");
  Graph = new Graphics();
  if (!Graph->IsReady()) {
    APP_LOG_ERROR("Graphics init failed (video out / frame buffers)");
    ShowFatalReason("Graphics failed — reboot PS4 and try again.");
  }
  APP_LOG_INFO("Graphics OK %dx%d", Graph->GetScreenWidth(), Graph->GetScreenHeight());
  logKernel(LL_Debug, "%s", "Initialize Resource...");
  Res = new Resource(this, Lang->GetTypefacePaths());
  if (Res->m_Typefaces.empty()) {
    APP_LOG_ERROR("Font load failed — check /app0/assets/fonts/NotoSans-Regular.ttf");
    ShowFatalReason("Font load failed. Reinstall PKG from /data/pkg/PS4-Linux-v*.pkg");
  }
  APP_LOG_INFO("Resource OK");

  // Load some needed module
  // sceSysmoduleLoadModule(SCE_SYSMDOULE_LIBIME);
  // sceSysmoduleLoadModule(SCE_SYSMODULE_IME_DIALOG);

  // Setup the default view
  logKernel(LL_Debug, "%s", "Initialize the Main View...");

  LinuxLoaderView *s_MainView = new LinuxLoaderView(this);
  m_CurrentView = s_MainView;
  APP_LOG_INFO("LinuxLoaderView ready");
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

  if (Graph == nullptr || !Graph->IsReady()) {
    while (1) {
      sceKernelUsleep(500000);
    }
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
  Graph->WaitFlip();

  if (m_CurrentView) {
    m_CurrentView->Render();
  } else {
    logKernel(LL_Debug, "%s", "No view setup!");
  }

  Graph->SwapBuffer(m_FlipArgs);
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

  // Main Loop
  while (m_IsRunning) {
    Update();
    Render();
  }
}
