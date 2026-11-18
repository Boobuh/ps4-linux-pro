// PS4 Linux — loads ps4-linux-loader kexec bin from internal HDD
#include "BuildVersion.h"
#include "LinuxLoaderView.h"
#include "Ps4LinuxUiTheme.h"

#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <string>

#include "App.h"
#include "AppFileLog.h"
#include "Controller.h"
#include "FailSafe.h"
#include "Graphics.h"
#include "LinuxBootConfig.h"
#include "LinuxInstallDetect.h"
#include "PlatformDetect.h"
#include "Resource.h"
#if !defined(PS4LINUX_NO_SETTINGS)
#include "SettingsView.h"
#endif
#include "Utility.h"
#include "libLog.h"
#include "notifi.h"

static bool pathReadable(const char *p_Path) {
  return p_Path != nullptr && access(p_Path, R_OK) == 0;
}

static std::string binPathForGoldHen(const std::string &path) {
  if (path.empty()) {
    return path;
  }
  if (path.size() >= 4 && path.compare(path.size() - 4, 4, ".bin") == 0) {
    return path;
  }
  if (path.size() >= 4 && path.compare(path.size() - 4, 4, ".elf") == 0) {
    const std::string bin = path.substr(0, path.size() - 4) + ".bin";
    if (pathReadable(bin.c_str())) {
      return bin;
    }
  }
  return path;
}

static std::string elfPathForShellcode(const std::string &path) {
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

static Color dimColor(Color c) {
  c.r = static_cast<uint8_t>(c.r * 3 / 4);
  c.g = static_cast<uint8_t>(c.g * 3 / 4);
  c.b = static_cast<uint8_t>(c.b * 3 / 4);
  return c;
}

/// GoldHEN socket needs a real kexec `.bin` (not ELF/FSELF). `linux-1024mb.bin` from sync is often ELF bytes.
static std::string pickGoldHenSocketBin() {
  static const char *kCandidates[] = {
      "/data/payloads/linux-1024mb.bin",
      "/data/payloads/payload-1100-1gb-pro-baikal.bin",
      "/data/payloads/linux-1gb-pro-baikal.bin",
      "/data/payloads/payload-1100-2gb-pro-baikal.bin",
      "/data/payloads/payload-1100-3gb-pro-baikal.bin",
      "/data/payloads/payload-1100-4gb-pro-baikal.bin",
  };
  for (const char *path : kCandidates) {
    if (pathReadable(path) && failSafeIsKexecBinPayload(path)) {
      return path;
    }
  }
  return {};
}

static constexpr int kArchPresets[] = {50, 75, 100, 125, 150, 200};
static constexpr int kArchPresetCount = static_cast<int>(sizeof(kArchPresets) / sizeof(kArchPresets[0]));
static constexpr int kArchPickerCustomIndex = kArchPresetCount;
static constexpr int kArchPickerCount = kArchPresetCount + 1;

static constexpr int kVramOptions[] = {512, 1024, 2048, 4096};
static constexpr int kVramOptionCount = static_cast<int>(sizeof(kVramOptions) / sizeof(kVramOptions[0]));

LinuxLoaderView::LinuxLoaderView(Application *p_App)
    : m_App(p_App), m_Launching(false), m_BootInProgress(false), m_LaunchBlockUi(false), m_LaunchFailed(false),
      m_LastLaunchTime(0), m_LaunchBlockStart(0), m_MenuIndex(0), m_SubScreen(SubScreen::None), m_PickerSelected(0),
      m_ManualArchGb(LinuxBootConfig::kArchGbDefault) {
  m_Config.Load();
  if (!pathReadable(LinuxBootConfig::kConfigPath)) {
    PlatformInfo info = DetectPlatform();
    ApplyRecommendedDefaults(m_Config, info);
  }
  m_Config.Normalize();
  RefreshPaths();
}

void LinuxLoaderView::RefreshPaths() {
  m_Config.Load();
  m_PayloadPath = m_Config.ResolvePayloadPath();
  m_Platform = DetectPlatform();
  m_Install = DetectLinuxInstallOnHdd();
  APP_LOG_INFO("Install detect: %s", m_Install.summaryLine.c_str());
  if (m_MenuIndex >= MainMenuCount()) {
    m_MenuIndex = MainMenuCount() - 1;
  }
  if (m_MenuIndex < 0) {
    m_MenuIndex = 0;
  }

  if (m_PayloadPath.empty()) {
    m_StatusLine = "Missing loader in /data/payloads/ (run Mac sync)";
  } else {
    m_StatusLine = std::string("Loader: ") + m_PayloadPath;
  }

  if (bootStackReady()) {
    m_BootCheckLine = m_Install.summaryLine;
  } else {
    m_BootCheckLine = "Missing bzImage/initramfs — run: swift tools/ps4-linux-sync.swift sync";
  }

  std::string hw;
  Utility::StrSprintf(hw, "Board: %s | Install %d GB | VRAM %d MB | %s", m_Platform.southbridgeName.c_str(),
                      m_Config.archGb, m_Config.vramMb, m_Config.verboseBoot ? "verbose HDMI" : "quiet boot");
  m_HardwareLine = hw;
}

void LinuxLoaderView::PersistConfigChoice(const char *what) {
  m_Config.Normalize();
  if (!m_Config.Save()) {
    APP_LOG_WARN("PersistConfigChoice: Save failed (%s)", what);
  }
  if (!m_Config.WriteBootFiles()) {
    APP_LOG_WARN("PersistConfigChoice: WriteBootFiles failed (%s)", what);
  }
  RefreshPaths();
  notifi(NULL, "%s", what);
}

void LinuxLoaderView::OpenInstallGbPicker() {
  APP_LOG_INFO("UI: install GB picker opened");
  m_SubScreen = SubScreen::PickInstallGb;
  m_PickerSelected = kArchPickerCustomIndex;
  for (int i = 0; i < kArchPresetCount; i++) {
    if (kArchPresets[i] == m_Config.archGb) {
      m_PickerSelected = i;
      break;
    }
  }
}

int LinuxLoaderView::MainMenuCount() const { return m_Install.IsReady() ? 5 : 4; }

LinuxLoaderView::MainMenuAction LinuxLoaderView::ActionForMenuIndex(int index) const {
  if (m_Install.IsReady()) {
    switch (index) {
    case 0:
      return MainMenuAction::PrimaryLaunch;
    case 1:
      return MainMenuAction::NewInstallWipe;
    case 2:
      return MainMenuAction::InstallGb;
    case 3:
      return MainMenuAction::Vram;
    default:
      return MainMenuAction::Refresh;
    }
  }
  switch (index) {
  case 0:
    return MainMenuAction::PrimaryLaunch;
  case 1:
    return MainMenuAction::InstallGb;
  case 2:
    return MainMenuAction::Vram;
  default:
    return MainMenuAction::Refresh;
  }
}

void LinuxLoaderView::BuildMenuLine(int index, bool selected, std::string &outLine) const {
  char detail[64];
  const char *title = "Menu";
  switch (ActionForMenuIndex(index)) {
  case MainMenuAction::PrimaryLaunch:
    if (m_Install.IsReady()) {
      title = "Boot installed Linux";
    } else if (m_Install.IsPartial()) {
      title = "Setup new install (fix partial)";
    } else {
      title = "Install Linux on HDD";
    }
    break;
  case MainMenuAction::NewInstallWipe:
    title = "Setup new install (wipes Arch.img)";
    break;
  case MainMenuAction::InstallGb:
    title = "Install partition size";
    std::snprintf(detail, sizeof(detail), " — %d GB", m_Config.archGb);
    outLine = std::string(selected ? "> " : "  ") + title + detail;
    return;
  case MainMenuAction::Vram:
    title = "Linux RAM (VRAM)";
    std::snprintf(detail, sizeof(detail), " — %d MB", m_Config.vramMb);
    outLine = std::string(selected ? "> " : "  ") + title + detail;
    return;
  case MainMenuAction::Refresh:
    title = "Refresh status";
    break;
  }
  outLine = std::string(selected ? "> " : "  ") + title;
}

void LinuxLoaderView::OpenVramPicker() {
  APP_LOG_INFO("UI: VRAM picker opened");
  m_SubScreen = SubScreen::PickVram;
  m_PickerSelected = 1;
  for (int i = 0; i < kVramOptionCount; i++) {
    if (kVramOptions[i] == m_Config.vramMb) {
      m_PickerSelected = i;
      break;
    }
  }
}

int LinuxLoaderView::UpdateSubScreen() {
  if (m_SubScreen == SubScreen::ConfirmReinstall) {
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
      m_SubScreen = SubScreen::None;
      return 0;
    }
    if (m_App->Ctrl->GetMenuConfirmPressed()) {
      m_SubScreen = SubScreen::None;
      m_App->Ctrl->ConsumeMenuConfirm();
      BeginLaunchBlockUi("Preparing fresh internal HDD install…");
      m_Launching = true;
      LaunchLinuxPayload(true);
      m_Launching = false;
    }
    return 0;
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
    m_SubScreen = SubScreen::None;
    return 0;
  }

  if (m_SubScreen == SubScreen::AdjustInstallGb) {
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_LEFT)) {
      m_ManualArchGb = LinuxBootConfig::ClampArchGb(m_ManualArchGb - 10);
    }
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_RIGHT)) {
      m_ManualArchGb = LinuxBootConfig::ClampArchGb(m_ManualArchGb + 10);
    }
    if (m_App->Ctrl->GetMenuConfirmPressed()) {
      m_Config.archGb = m_ManualArchGb;
      PersistConfigChoice("Install size saved");
      m_SubScreen = SubScreen::None;
      m_App->Ctrl->ConsumeMenuConfirm();
    }
    return 0;
  }

  const int pickerCount =
      (m_SubScreen == SubScreen::PickInstallGb) ? kArchPickerCount : kVramOptionCount;

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_UP) && m_PickerSelected > 0) {
    m_PickerSelected--;
  }
  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_DOWN) && m_PickerSelected + 1 < pickerCount) {
    m_PickerSelected++;
  }

  const bool subConfirm = m_App->Ctrl->GetMenuConfirmPressed();
  if (!subConfirm) {
    return 0;
  }
  APP_LOG_INFO("Submenu confirm sub=%d picker=%d", static_cast<int>(m_SubScreen), m_PickerSelected);
  m_App->Ctrl->ConsumeMenuConfirm();

  if (m_SubScreen == SubScreen::PickInstallGb) {
    if (m_PickerSelected == kArchPickerCustomIndex) {
      m_ManualArchGb = LinuxBootConfig::ClampArchGb(m_Config.archGb);
      m_SubScreen = SubScreen::AdjustInstallGb;
      return 0;
    }
    m_Config.archGb = kArchPresets[m_PickerSelected];
    PersistConfigChoice("Install size saved");
    m_SubScreen = SubScreen::None;
    return 0;
  }

  if (m_SubScreen == SubScreen::PickVram) {
    m_Config.vramMb = kVramOptions[m_PickerSelected];
    PersistConfigChoice("Linux RAM saved");
    m_SubScreen = SubScreen::None;
  }
  return 0;
}

int LinuxLoaderView::RenderSubScreen() {
  Color bg = PS4LINUX_UI_BG_PANEL;
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color hi = {0x44, 0xFF, 0xAA, 0xFF};
  Color dim = {0x66, 0x88, 0xAA, 0xFF};
  Color rowHi = {0x28, 0x58, 0x88, 0xFF};
  Color rowLo = {0x10, 0x32, 0x72, 0xFF};

  m_App->Graph->FrameBufferFill(bg);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);

  if (m_SubScreen == SubScreen::ConfirmReinstall) {
    m_App->Graph->DrawText("Wipe and reinstall?", m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);
    m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
    m_App->Graph->DrawText("Deletes /user/home/Arch.img and install logs.", m_App->Res->m_Typefaces, BORDER_X, 160,
                           hi, hi);
    m_App->Graph->DrawText("Next boot runs a full install at your chosen GB size.", m_App->Res->m_Typefaces, BORDER_X,
                           200, dim, dim);
    m_App->Graph->DrawText("OK/Cross: wipe and install   Circle: cancel", m_App->Res->m_Typefaces, BORDER_X, 280, dim,
                           dim);
    return 0;
  }

  if (m_SubScreen == SubScreen::AdjustInstallGb) {
    m_App->Graph->DrawText("Custom install size", m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);
    m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
    char line[96];
    std::snprintf(line, sizeof(line), "Partition: %d GB  (min %d, default %d)", m_ManualArchGb,
                  LinuxBootConfig::kArchGbMin, LinuxBootConfig::kArchGbDefault);
    m_App->Graph->DrawText(line, m_App->Res->m_Typefaces, BORDER_X, 160, hi, hi);
    m_App->Graph->DrawText("Left/Right: ±10 GB   OK/Cross: save   Circle: cancel", m_App->Res->m_Typefaces, BORDER_X,
                           220, dim, dim);
    return 0;
  }

  const char *title = (m_SubScreen == SubScreen::PickInstallGb) ? "Install partition size" : "Linux RAM (loader VRAM)";
  m_App->Graph->DrawText(title, m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE - 2);
  m_App->Graph->DrawText("Used before Start Linux — saved to ps4-install-gb.txt / vram.txt", m_App->Res->m_Typefaces,
                         BORDER_X, 118, dim, dim);

  const int rowY0 = 170;
  const int rowH = 40;
  const int pickerCount =
      (m_SubScreen == SubScreen::PickInstallGb) ? kArchPickerCount : kVramOptionCount;

  for (int i = 0; i < pickerCount; i++) {
    char label[96];
    if (m_SubScreen == SubScreen::PickInstallGb) {
      if (i == kArchPickerCustomIndex) {
        std::snprintf(label, sizeof(label), "Custom (fine-tune, min %d GB)", LinuxBootConfig::kArchGbMin);
      } else {
        std::snprintf(label, sizeof(label), "%d GB%s", kArchPresets[i],
                      kArchPresets[i] == LinuxBootConfig::kArchGbDefault ? " (default)" : "");
      }
    } else {
      std::snprintf(label, sizeof(label), "%d MB%s", kVramOptions[i], kVramOptions[i] == 1024 ? " (Baikal Pro)" : "");
    }
    const bool sel = (i == m_PickerSelected);
    const std::string row = std::string(sel ? "> " : "  ") + label;
    m_App->Graph->DrawRectangle(BORDER_X, rowY0 + i * rowH, 920, rowH - 4, sel ? rowHi : rowLo);
    m_App->Graph->DrawText(row, m_App->Res->m_Typefaces, BORDER_X + 8, rowY0 + i * rowH + 8, sel ? hi : dim,
                           sel ? hi : dim);
  }

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE - 2);
  if (m_App->Ctrl->HasTvRemotePad()) {
    m_App->Graph->DrawText("Up/Down move   Hold Down ~1s = confirm   Options key ignored", m_App->Res->m_Typefaces,
                           BORDER_X, 520, dim, dim);
  } else {
    m_App->Graph->DrawText("Up/Down   OK/Cross confirm   Circle back", m_App->Res->m_Typefaces, BORDER_X, 520, dim,
                           dim);
  }
  return 0;
}

void LinuxLoaderView::BeginLaunchBlockUi(const char *phaseLine) {
  m_LaunchBlockUi = true;
  m_LaunchFailed = false;
  m_BootInProgress = false;
  m_LaunchBlockStart = sceKernelGetProcessTime();
  m_LaunchPhaseLine = phaseLine;
}

void LinuxLoaderView::EndLaunchBlockUiFailed(const char *detail) {
  m_LaunchFailed = true;
  m_BootInProgress = false;
  m_LaunchPhaseLine = detail;
  APP_LOG_WARN("Launch blocked UI failure: %s", detail);
}

float LinuxLoaderView::LaunchProgress01() const {
  if (m_LaunchFailed) {
    return 0.0f;
  }
  const uint64_t now = sceKernelGetProcessTime();
  const float elapsedSec =
      m_LaunchBlockStart > 0 ? static_cast<float>(now - m_LaunchBlockStart) / 1000000.0f : 0.0f;
  if (m_Launching) {
    const float pulse = 0.12f + 0.08f * (static_cast<int>(elapsedSec) % 2);
    return pulse;
  }
  if (m_BootInProgress) {
    // Indeterminate through ~5 min, then hold near full while HDMI install continues off-console.
    return elapsedSec < 300.0f ? 0.18f + (elapsedSec / 300.0f) * 0.77f : 0.95f;
  }
  return 0.05f;
}

int LinuxLoaderView::RenderLaunchBlockUi() {
  const int h = m_App->Graph->GetScreenHeight();
  Color bg = PS4LINUX_UI_BG_PANEL;
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color sub = {0xAA, 0xCC, 0xFF, 0xFF};
  Color warn = {0xFF, 0xAA, 0x44, 0xFF};
  Color err = {0xFF, 0x66, 0x66, 0xFF};
  Color barBg = {0x10, 0x32, 0x72, 0xFF};
  Color barFill = m_LaunchFailed ? err : Color{0x44, 0xFF, 0xAA, 0xFF};

  m_App->Graph->FrameBufferFill(bg);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);
  m_App->Graph->DrawText(m_LaunchFailed ? "Linux launch failed" : "Installing / booting Linux",
                         m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
  m_App->Graph->DrawText(m_LaunchPhaseLine, m_App->Res->m_Typefaces, BORDER_X, 150,
                         m_LaunchFailed ? warn : sub, m_LaunchFailed ? warn : sub);

  const int barX = BORDER_X;
  const int barY = 220;
  const int barW = 920;
  const int barH = 28;
  const float progress = LaunchProgress01();
  m_App->Graph->DrawRectangle(barX, barY, barW, barH, barBg);
  const int fillW = static_cast<int>(barW * progress);
  if (fillW > 0) {
    m_App->Graph->DrawRectangle(barX, barY, fillW, barH, barFill);
  }

  char pct[32];
  std::snprintf(pct, sizeof(pct), "%d%%", static_cast<int>(progress * 100.0f + 0.5f));
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE - 2);
  m_App->Graph->DrawText(pct, m_App->Res->m_Typefaces, barX + barW - 56, barY + 4, sub, sub);

  if (!m_LaunchFailed && m_BootInProgress) {
    m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
    m_App->Graph->DrawText("HDMI may go blank 3–5 min, then Step 1/2/3 on internal HDD.", m_App->Res->m_Typefaces,
                           BORDER_X, 280, sub, sub);
    m_App->Graph->DrawText("Full HDD install often 30–90+ min. Do not power off during steps.", m_App->Res->m_Typefaces,
                           BORDER_X, 320, warn, warn);
    m_App->Graph->DrawText("If you are still in this app, kexec did not run — Circle to dismiss and fix BinLoader.",
                           m_App->Res->m_Typefaces, BORDER_X, 360, dimColor(sub), dimColor(sub));
  }

  if (m_LaunchFailed) {
    m_App->Graph->DrawText("Fix on PS4: GoldHEN → Servers → BinLoader ON (port 9090), then retry.",
                           m_App->Res->m_Typefaces, BORDER_X, 280, warn, warn);
    m_App->Graph->DrawText("Circle / Back: return to menu", m_App->Res->m_Typefaces, BORDER_X, h - 80, sub, sub);
  } else if (m_Launching) {
    m_App->Graph->DrawText("Please wait — menu is locked while boot files are prepared.", m_App->Res->m_Typefaces,
                           BORDER_X, 280, sub, sub);
  }

  return 0;
}

bool LinuxLoaderView::LaunchLinuxPayload(bool wipeForNewInstall) {
  if (wipeForNewInstall) {
    m_LaunchPhaseLine = "Removing old Arch.img for fresh install…";
    if (!WipeLinuxInstallForReinstall()) {
      APP_LOG_ERROR("LaunchLinux: wipe for reinstall failed");
      EndLaunchBlockUiFailed("Could not delete Arch.img — check GoldHEN FTP paths");
      return false;
    }
    RefreshPaths();
  }

  m_LaunchPhaseLine = "Writing boot files (ps4-install-gb.txt, vram.txt)…";

  if (m_PayloadPath.empty()) {
    APP_LOG_ERROR("LaunchLinux: no payload path");
    EndLaunchBlockUiFailed("No linux loader in /data/payloads/ — run Mac sync");
    return false;
  }

  if (!bootStackReady()) {
    APP_LOG_WARN("LaunchLinux: missing bzImage or initramfs under /data/linux/boot/");
    EndLaunchBlockUiFailed("Missing bzImage or initramfs — run Mac sync to /data/linux/boot/");
    return false;
  }

  if (!m_Config.WriteBootFiles()) {
    APP_LOG_ERROR("LaunchLinux: WriteBootFiles failed before payload");
    EndLaunchBlockUiFailed("Could not write /data/linux/boot/ — run Mac sync");
    return false;
  }

  m_LaunchPhaseLine = "Sending kexec loader to GoldHEN (127.0.0.1:9090 / :9021)…";

  std::string socketPath = pickGoldHenSocketBin();
  if (socketPath.empty()) {
    socketPath = binPathForGoldHen(m_PayloadPath);
  }
  const std::string shellcodePath = elfPathForShellcode(m_PayloadPath);
  const bool socketOk = failSafeIsKexecBinPayload(socketPath.c_str());
  const bool shellcodeOk = pathReadable(shellcodePath.c_str());

  if (!socketOk && !shellcodeOk) {
    APP_LOG_ERROR("LaunchLinux: no valid loader (.bin or .elf) under /data/payloads/");
    EndLaunchBlockUiFailed("Missing valid kexec .bin — run Mac sync to /data/payloads/");
    return false;
  }

  logKernel(LL_Info, "PS4 Linux payload socket=%s shellcode=%s", socketPath.c_str(), shellcodePath.c_str());
  APP_LOG_INFO("LaunchLinux socket=%s (ok=%d) shellcode=%s (ok=%d) profile=%s vram=%d", socketPath.c_str(),
               socketOk ? 1 : 0, shellcodePath.c_str(), shellcodeOk ? 1 : 0, m_Config.PayloadProfileLabel().c_str(),
               m_Config.vramMb);

  if (!Utility::IsPS5()) {
    bool sent = false;
    bool viaSocket = false;
    if (socketOk) {
      const bool hen = Utility::SendPayloadSocket(m_App, "127.0.0.1", 9090, socketPath);
      viaSocket = hen || Utility::SendPayloadSocket(m_App, "127.0.0.1", 9021, socketPath);
      sent = viaSocket;
    }
    if (!sent) {
      APP_LOG_ERROR("LaunchLinux: GoldHEN/Mira payload socket refused (errno 61)");
      EndLaunchBlockUiFailed(
          "Connection refused on 127.0.0.1:9090 — enable GoldHEN BinLoader, then retry.");
      return false;
    }
    APP_LOG_INFO("LaunchLinux: sent via %s", viaSocket ? "socket" : "shellcode");
    m_BootInProgress = true;
    m_LaunchPhaseLine = "Kexec sent — waiting for Linux on HDMI (internal HDD install next)…";
  } else {
    APP_LOG_ERROR("LaunchLinux: PS5 not supported");
    EndLaunchBlockUiFailed("PS5 is not supported");
    return false;
  }

  m_LastLaunchTime = sceKernelGetProcessTime();
  return true;
}

int LinuxLoaderView::Update() {
  if (m_SubScreen != SubScreen::None) {
    return UpdateSubScreen();
  }

  if (m_LaunchBlockUi) {
    if (m_LaunchFailed &&
        (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE) ||
         m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CROSS))) {
      m_LaunchBlockUi = false;
      m_LaunchFailed = false;
      m_BootInProgress = false;
      m_App->Ctrl->ConsumeMenuConfirm();
      APP_LOG_INFO("User dismissed launch failure screen");
      return 0;
    }
    if (m_BootInProgress && m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
      m_LaunchBlockUi = false;
      m_BootInProgress = false;
      APP_LOG_INFO("User cancelled boot-wait screen");
      return 0;
    }
    return 0;
  }

  if (m_Launching) {
    return 0;
  }

  const bool confirm = m_App->Ctrl->GetMenuConfirmPressed();

  if (!confirm) {
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_UP) && m_MenuIndex > 0) {
      m_MenuIndex--;
    }
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_DOWN) && m_MenuIndex + 1 < MainMenuCount()) {
      m_MenuIndex++;
    }
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_SQUARE)) {
    RefreshPaths();
    notifi(NULL, "Status refreshed");
    return 0;
  }

#if !defined(PS4LINUX_NO_SETTINGS)
  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_TRIANGLE)) {
    SettingsView *settings = new SettingsView(m_App, this);
    m_App->ChangeView(settings);
    return 0;
  }
#endif

  if (!confirm) {
    return 0;
  }

  const MainMenuAction action = ActionForMenuIndex(m_MenuIndex);
  switch (action) {
  case MainMenuAction::InstallGb:
    OpenInstallGbPicker();
    m_App->Ctrl->ConsumeMenuConfirm();
    return 0;
  case MainMenuAction::Vram:
    OpenVramPicker();
    m_App->Ctrl->ConsumeMenuConfirm();
    return 0;
  case MainMenuAction::Refresh:
    RefreshPaths();
    notifi(NULL, "Status refreshed");
    m_App->Ctrl->ConsumeMenuConfirm();
    return 0;
  case MainMenuAction::NewInstallWipe:
    m_SubScreen = SubScreen::ConfirmReinstall;
    m_App->Ctrl->ConsumeMenuConfirm();
    return 0;
  case MainMenuAction::PrimaryLaunch:
    break;
  }

  APP_LOG_INFO("Menu confirm primary launch index=%d (installed=%d partial=%d)", m_MenuIndex,
               m_Install.IsReady() ? 1 : 0, m_Install.IsPartial() ? 1 : 0);

  const uint64_t now = sceKernelGetProcessTime();
  if (m_LastLaunchTime != 0 && now < m_LastLaunchTime + (5 * 1000000ULL)) {
    m_App->Ctrl->ConsumeMenuConfirm();
    return 0;
  }
  BeginLaunchBlockUi(m_Install.IsReady() ? "Booting installed Linux on internal HDD…"
                                         : "Starting internal HDD Linux install…");
  m_Launching = true;
  LaunchLinuxPayload(m_Install.IsPartial());
  m_Launching = false;
  m_App->Ctrl->ConsumeMenuConfirm();

  return 0;
}

int LinuxLoaderView::Render() {
  if (m_SubScreen != SubScreen::None) {
    return RenderSubScreen();
  }

  if (m_LaunchBlockUi) {
    return RenderLaunchBlockUi();
  }

  const int h = m_App->Graph->GetScreenHeight();

  Color bg = PS4LINUX_UI_BG;
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color sub = {0xAA, 0xCC, 0xFF, 0xFF};
  Color warn = {0xFF, 0xAA, 0x44, 0xFF};

  m_App->Graph->FrameBufferFill(bg);

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);
  m_App->Graph->DrawText("PS4 Linux", m_App->Res->m_Typefaces, BORDER_X, 80, titleC, titleC);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE - 2);
  m_App->Graph->DrawText("Baikal: install and run Linux from internal HDD (no USB during boot)", m_App->Res->m_Typefaces,
                         BORDER_X, 118, sub, sub);

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
  m_App->Graph->DrawText(m_HardwareLine, m_App->Res->m_Typefaces, BORDER_X, 160, sub, sub);
  m_App->Graph->DrawText(m_StatusLine, m_App->Res->m_Typefaces, BORDER_X, 210, sub, sub);
  m_App->Graph->DrawText(m_BootCheckLine, m_App->Res->m_Typefaces, BORDER_X, 260, bootStackReady() ? sub : warn,
                         bootStackReady() ? sub : warn);

  Color hi = {0x44, 0xFF, 0xAA, 0xFF};
  Color dim = {0x66, 0x88, 0xAA, 0xFF};
  for (int i = 0; i < MainMenuCount(); i++) {
    const bool sel = (i == m_MenuIndex);
    std::string line;
    BuildMenuLine(i, sel, line);
    m_App->Graph->DrawText(line, m_App->Res->m_Typefaces, BORDER_X, 300 + i * 36, sel ? hi : dim, sel ? hi : dim);
  }

  m_App->Graph->DrawText("Set install size & RAM before a new install (min 50 GB, default 100 GB).",
                         m_App->Res->m_Typefaces, BORDER_X, h - 260, titleC, titleC);
  m_App->Graph->DrawText(m_Install.IsReady() ? "Boot = kexec into existing Arch.img" : "Install = kexec then HDD format/extract",
                         m_App->Res->m_Typefaces, BORDER_X, h - 220, sub, sub);
  if (m_App->Ctrl->HasTvRemotePad()) {
    m_App->Graph->DrawText("Up/Down: select   Hold Down ~1s on row = confirm   Circle: back", m_App->Res->m_Typefaces,
                           BORDER_X, h - 200, sub, sub);
  } else {
    m_App->Graph->DrawText("Up/Down: select   OK / Cross (Enter): confirm   Circle: back", m_App->Res->m_Typefaces,
                           BORDER_X, h - 200, sub, sub);
  }
#if !defined(PS4LINUX_NO_SETTINGS)
  m_App->Graph->DrawText("Triangle = settings (lists for each option)", m_App->Res->m_Typefaces, BORDER_X, h - 120, sub,
                         sub);
#else
  m_App->Graph->DrawText("Settings: install stage-3 PKG (full menu)", m_App->Res->m_Typefaces, BORDER_X, h - 120, sub,
                         sub);
#endif
  m_App->Graph->DrawText("Refresh: Square or R / Backspace", m_App->Res->m_Typefaces, BORDER_X, h - 80, sub, sub);
  m_App->Graph->DrawText("Input: DualShock and HDMI TV remote (e.g. RMT-TX300E) via Bravia Sync", m_App->Res->m_Typefaces,
                         BORDER_X, h - 40, sub, sub);
  std::string verLine = std::string("v") + PS4_LINUX_PKG_VERSION + "  APP " + PS4_LINUX_PKG_APP_VER;
  m_App->Graph->DrawText(verLine, m_App->Res->m_Typefaces, BORDER_X, h - 8, sub, sub);
  return 0;
}
