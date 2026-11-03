// PS4 Linux — loads ps4-linux-loader kexec bin from internal HDD
#include "BuildVersion.h"
#include "LinuxLoaderView.h"

#include <unistd.h>

#include <cerrno>
#include <string>

#include "App.h"
#include "AppFileLog.h"
#include "Controller.h"
#include "Graphics.h"
#include "LinuxBootConfig.h"
#include "PlatformDetect.h"
#include "Resource.h"
#include "SettingsView.h"
#include "Utility.h"
#include "libLog.h"
#include "notifi.h"

static bool pathReadable(const char *p_Path) {
  return p_Path != nullptr && access(p_Path, R_OK) == 0;
}

static std::string preferElfPayload(const std::string &path) {
  if (path.empty()) {
    return path;
  }
  if (path.size() >= 4 && path.compare(path.size() - 4, 4, ".elf") == 0) {
    return path;
  }
  if (path.size() >= 4 && path.compare(path.size() - 4, 4, ".bin") == 0) {
    const std::string elf = path.substr(0, path.size() - 4) + ".elf";
    if (pathReadable(elf.c_str())) {
      return elf;
    }
  }
  return path;
}

static bool bootStackReady() {
  return pathReadable("/data/linux/boot/bzImage") && pathReadable("/data/linux/boot/initramfs.cpio.gz");
}

LinuxLoaderView::LinuxLoaderView(Application *p_App)
    : m_App(p_App), m_Launching(false), m_BootInProgress(false), m_LastLaunchTime(0) {
  m_Config.Load();
  if (!pathReadable(LinuxBootConfig::kConfigPath)) {
    PlatformInfo info = DetectPlatform();
    ApplyRecommendedDefaults(m_Config, info);
  }
  RefreshPaths();
}

void LinuxLoaderView::RefreshPaths() {
  m_Config.Load();
  m_PayloadPath = m_Config.ResolvePayloadPath();
  m_Platform = DetectPlatform();

  if (m_PayloadPath.empty()) {
    m_StatusLine = "Missing loader in /data/payloads/ (run Mac sync)";
  } else {
    m_StatusLine = std::string("Loader: ") + m_PayloadPath;
  }

  if (bootStackReady()) {
    m_BootCheckLine = "Boot OK: /data/linux/boot/ (unplug USB storage)";
  } else {
    m_BootCheckLine = "Missing bzImage or initramfs in /data/linux/boot/";
  }

  std::string hw;
  Utility::StrSprintf(hw, "Board: %s | VRAM %d MB | %s", m_Platform.southbridgeName.c_str(), m_Config.vramMb,
                      m_Config.verboseBoot ? "verbose HDMI" : "quiet boot");
  m_HardwareLine = hw;
}

bool LinuxLoaderView::LaunchLinuxPayload() {
  if (m_PayloadPath.empty()) {
    APP_LOG_ERROR("LaunchLinux: no payload path");
    notifi(NULL, "No linux loader payload on /data/payloads/");
    return false;
  }

  if (!bootStackReady()) {
    APP_LOG_WARN("LaunchLinux: missing bzImage or initramfs under /data/linux/boot/");
    notifi(NULL, "Upload /data/linux/boot/ first (Mac sync)");
    return false;
  }

  if (!m_Config.WriteBootFiles()) {
    APP_LOG_ERROR("LaunchLinux: WriteBootFiles failed before payload");
    notifi(NULL, "Could not write boot config — open Settings, save");
    return false;
  }

  const std::string launchPath = preferElfPayload(m_PayloadPath);
  logKernel(LL_Info, "PS4 Linux: %s", launchPath.c_str());
  APP_LOG_INFO("LaunchLinux payload=%s (profile=%s) vram=%d", launchPath.c_str(),
               m_Config.PayloadProfileLabel().c_str(), m_Config.vramMb);
  notifi(NULL, "Starting Linux (1024MB loader)… HDMI may go black 3-5 min.");

  if (!Utility::IsPS5()) {
    const bool hen = Utility::SendPayloadSocket(m_App, "127.0.0.1", 9090, launchPath);
    const bool mira = hen || Utility::SendPayloadSocket(m_App, "127.0.0.1", 9021, launchPath);
    if (!mira) {
      APP_LOG_WARN("LaunchLinux: GoldHEN/Mira socket failed, trying in-process .elf");
      Utility::LaunchShellcode(m_App, launchPath);
    }
    APP_LOG_INFO("LaunchLinux: sent %s via %s", launchPath.c_str(), mira ? "socket" : "shellcode");
    m_BootInProgress = true;
  } else {
    APP_LOG_ERROR("LaunchLinux: PS5 not supported");
    notifi(NULL, "PS5 not supported");
    return false;
  }

  m_LastLaunchTime = sceKernelGetProcessTime();
  return true;
}

int LinuxLoaderView::Update() {
  if (m_BootInProgress && m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
    m_BootInProgress = false;
    APP_LOG_INFO("User cancelled boot-wait screen");
    return 0;
  }

  if (m_BootInProgress) {
    return 0;
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_SQUARE)) {
    RefreshPaths();
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_TRIANGLE)) {
    SettingsView *settings = new SettingsView(m_App, this);
    m_App->ChangeView(settings);
    return 0;
  }

  if (m_Launching) {
    return 0;
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CROSS)) {
    const uint64_t now = sceKernelGetProcessTime();
    if (m_LastLaunchTime != 0 && now < m_LastLaunchTime + (5 * 1000000ULL)) {
      return 0;
    }
    m_Launching = true;
    LaunchLinuxPayload();
    m_Launching = false;
  }

  return 0;
}

int LinuxLoaderView::Render() {
  const int h = m_App->Graph->GetScreenHeight();
  const int w = m_App->Graph->GetScreenWidth();

  Color bg = {0x10, 0x18, 0x28, 0xFF};
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color sub = {0xAA, 0xCC, 0xFF, 0xFF};
  Color warn = {0xFF, 0xAA, 0x44, 0xFF};

  m_App->Graph->DrawRectangle(0, 0, w, h, bg);

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);
  m_App->Graph->DrawText("PS4 Linux", m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
  m_App->Graph->DrawText(m_HardwareLine, m_App->Res->m_Typefaces, BORDER_X, 160, sub, sub);
  m_App->Graph->DrawText(m_StatusLine, m_App->Res->m_Typefaces, BORDER_X, 210, sub, sub);
  m_App->Graph->DrawText(m_BootCheckLine, m_App->Res->m_Typefaces, BORDER_X, 260, bootStackReady() ? sub : warn,
                         bootStackReady() ? sub : warn);

  if (m_BootInProgress) {
    Color hi = {0x44, 0xFF, 0xAA, 0xFF};
    m_App->Graph->DrawText("Linux boot sent — HDMI may show penguin then install text.", m_App->Res->m_Typefaces,
                           BORDER_X, 320, hi, hi);
    m_App->Graph->DrawText("If you are back here: kernel failed (Baikal Pro). Check FTP logs.", m_App->Res->m_Typefaces,
                           BORDER_X, 370, warn, warn);
    m_App->Graph->DrawText("Circle = cancel boot-wait screen", m_App->Res->m_Typefaces, BORDER_X, h - 160, sub, sub);
  } else {
    m_App->Graph->DrawText("Cross = boot Linux", m_App->Res->m_Typefaces, BORDER_X, h - 160, titleC, titleC);
  }
  m_App->Graph->DrawText("Triangle = settings (lists for each option)", m_App->Res->m_Typefaces, BORDER_X, h - 120, sub, sub);
  m_App->Graph->DrawText("Square = refresh", m_App->Res->m_Typefaces, BORDER_X, h - 80, sub, sub);
  std::string verLine = std::string("v") + PS4_LINUX_PKG_VERSION + "  APP " + PS4_LINUX_PKG_APP_VER;
  m_App->Graph->DrawText(verLine, m_App->Res->m_Typefaces, BORDER_X, h - 40, sub, sub);
  return 0;
}
