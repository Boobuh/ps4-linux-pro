#include "SettingsView.h"

#include <algorithm>

#include "App.h"
#include "AppFileLog.h"
#include "Controller.h"
#include "Graphics.h"
#include "Resource.h"
#include "Utility.h"
#include "notifi.h"

SettingsView::SettingsView(Application *p_App, View *p_ReturnView)
    : m_App(p_App),
      m_ReturnView(p_ReturnView),
      m_Screen(SettingsScreen::Main),
      m_MainSelected(0),
      m_PickerSelected(0),
      m_PickerKind(SettingKind::Info) {
  m_Platform = DetectPlatform();
  std::string existing;
  if (Utility::ReadTextFile(LinuxBootConfig::kConfigPath, existing)) {
    m_Config.Load();
  } else {
    ApplyRecommendedDefaults(m_Config, m_Platform);
  }
  APP_LOG_INFO("Settings opened southbridge=%s detect=%s", m_Platform.southbridgeName.c_str(),
               m_Platform.detectSource.c_str());
  RebuildMainMenu();
}

void SettingsView::RebuildMainMenu() {
  m_MainItems.clear();

  std::string sb = m_Platform.southbridgeName;
  if (!m_Platform.southbridgeId.empty()) {
    sb += " " + m_Platform.southbridgeId;
  }
  m_MainItems.push_back({"Southbridge", sb, SettingKind::Info, false});
  m_MainItems.push_back({"Console", m_Platform.consoleLine, SettingKind::Info, false});
  m_MainItems.push_back({"Firmware", m_Platform.firmwareLine, SettingKind::Info, false});

  std::string vram;
  Utility::StrSprintf(vram, "%d MB", m_Config.vramMb);
  m_MainItems.push_back({"Loader VRAM", vram, SettingKind::Vram, true});

  m_MainItems.push_back({"Kexec payload", m_Config.PayloadProfileLabel(), SettingKind::Payload, true});
  m_MainItems.push_back({"Root install", m_Config.InstallTargetLabel(), SettingKind::InstallTarget, true});

  std::string gb;
  Utility::StrSprintf(gb, "%d GB", m_Config.archGb);
  m_MainItems.push_back({"Arch partition size", gb, SettingKind::ArchGb, true});

  m_MainItems.push_back({"Verbose HDMI log", m_Config.verboseBoot ? "On" : "Off", SettingKind::VerboseBoot, true});

  m_MainItems.push_back({"---", "", SettingKind::Info, false});
  m_MainItems.push_back({"Re-detect hardware", "Refresh board info", SettingKind::RedetectHardware, true});
  m_MainItems.push_back({"Apply recommended", "Best defaults for detected board", SettingKind::ApplyRecommended, true});
  m_MainItems.push_back({"Save boot files", "Write vram.txt, bootargs, install size", SettingKind::SaveBootFiles, true});
  m_MainItems.push_back({"Debug log (FTP)", AppFileLog::LogPath(), SettingKind::Info, false});

  if (m_MainSelected >= MainItemCount()) {
    m_MainSelected = std::max(0, MainItemCount() - 1);
  }
}

int SettingsView::MainItemCount() const { return static_cast<int>(m_MainItems.size()); }

void SettingsView::OpenPicker(SettingKind kind) {
  m_PickerKind = kind;
  m_PickerLabels.clear();
  m_PickerSelected = 0;

  switch (kind) {
  case SettingKind::Vram:
    m_PickerTitle = "Loader VRAM";
    m_PickerLabels = {"512 MB", "1024 MB (recommended Baikal Pro)", "2048 MB", "4096 MB"};
    for (size_t i = 0; i < m_PickerLabels.size(); i++) {
      const int v[] = {512, 1024, 2048, 4096};
      if (v[i] == m_Config.vramMb) {
        m_PickerSelected = static_cast<int>(i);
      }
    }
    break;
  case SettingKind::Payload:
    m_PickerTitle = "Kexec payload";
    m_PickerLabels = {"Auto (best for board)", "Pro Baikal 1 GB", "Generic 1024 MB"};
    m_PickerSelected = static_cast<int>(m_Config.payload);
    break;
  case SettingKind::InstallTarget:
    m_PickerTitle = "Root install";
    m_PickerLabels = {"Internal HDD (synced path)", "USB stick (not in Mac sync)"};
    m_PickerSelected = (m_Config.installTarget == InstallTarget::UsbStick) ? 1 : 0;
    break;
  case SettingKind::ArchGb:
    m_PickerTitle = "Arch partition size";
    m_PickerLabels = {"50 GB (recommended)", "75 GB", "100 GB", "150 GB"};
    {
      const int sizes[] = {50, 75, 100, 150};
      for (int i = 0; i < 4; i++) {
        if (sizes[i] == m_Config.archGb) {
          m_PickerSelected = i;
        }
      }
    }
    break;
  case SettingKind::VerboseBoot:
    m_PickerTitle = "Verbose HDMI log";
    m_PickerLabels = {"On — show install steps on TV", "Off — quiet kernel"};
    m_PickerSelected = m_Config.verboseBoot ? 0 : 1;
    break;
  default:
    return;
  }

  m_Screen = SettingsScreen::Picker;
}

void SettingsView::ApplyPickerChoice(int index) {
  if (index < 0 || index >= static_cast<int>(m_PickerLabels.size())) {
    return;
  }

  switch (m_PickerKind) {
  case SettingKind::Vram: {
    const int v[] = {512, 1024, 2048, 4096};
    m_Config.vramMb = v[index];
    break;
  }
  case SettingKind::Payload:
    m_Config.payload = static_cast<PayloadProfile>(index);
    break;
  case SettingKind::InstallTarget:
    m_Config.installTarget = (index == 1) ? InstallTarget::UsbStick : InstallTarget::InternalHdd;
    break;
  case SettingKind::ArchGb: {
    const int sizes[] = {50, 75, 100, 150};
    m_Config.archGb = sizes[index];
    break;
  }
  case SettingKind::VerboseBoot:
    m_Config.verboseBoot = (index == 0);
    break;
  default:
    break;
  }

  m_Screen = SettingsScreen::Main;
  RebuildMainMenu();
}

void SettingsView::ApplyRecommended() {
  ApplyRecommendedDefaults(m_Config, m_Platform);
  m_Status = "Applied recommended profile for " + m_Platform.southbridgeName;
  RebuildMainMenu();
  notifi(NULL, "%s", m_Status.c_str());
}

void SettingsView::SaveBootFiles() {
  if (m_Config.WriteBootFiles()) {
    m_Status = "Saved vram.txt, bootargs.txt, ps4-install-gb.txt";
    notifi(NULL, "%s", m_Status.c_str());
  } else {
    m_Status = "Save failed — check /data/linux/boot/";
    notifi(NULL, "%s", m_Status.c_str());
  }
}

int SettingsView::Update() {
  if (m_Screen == SettingsScreen::Picker) {
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
      m_Screen = SettingsScreen::Main;
      return 0;
    }
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_UP) && m_PickerSelected > 0) {
      m_PickerSelected--;
    }
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_DOWN) &&
        m_PickerSelected + 1 < static_cast<int>(m_PickerLabels.size())) {
      m_PickerSelected++;
    }
    if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CROSS)) {
      ApplyPickerChoice(m_PickerSelected);
    }
    return 0;
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CIRCLE)) {
    m_App->ChangeView(m_ReturnView);
    return 0;
  }

  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_UP) && m_MainSelected > 0) {
    m_MainSelected--;
  }
  if (m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_DOWN) && m_MainSelected + 1 < MainItemCount()) {
    m_MainSelected++;
  }

  if (!m_App->Ctrl->GetButtonPressed(ORBIS_PAD_BUTTON_CROSS)) {
    return 0;
  }

  const MenuItem &item = m_MainItems[static_cast<size_t>(m_MainSelected)];
  if (!item.selectable || item.kind == SettingKind::Info) {
    return 0;
  }

  switch (item.kind) {
  case SettingKind::Vram:
  case SettingKind::Payload:
  case SettingKind::InstallTarget:
  case SettingKind::ArchGb:
  case SettingKind::VerboseBoot:
    OpenPicker(item.kind);
    break;
  case SettingKind::RedetectHardware:
    m_Platform = DetectPlatform();
    m_Status = "Hardware re-detected";
    RebuildMainMenu();
    break;
  case SettingKind::ApplyRecommended:
    ApplyRecommended();
    break;
  case SettingKind::SaveBootFiles:
    SaveBootFiles();
    break;
  default:
    break;
  }
  return 0;
}

static void drawMenuRow(Graphics *g, Resource *res, int x, int y, int w, int h, const std::string &title,
                        const std::string &subtitle, bool selected, Color text, Color active, Color inactive) {
  g->DrawRectangle(x, y, w, h, selected ? active : inactive);
  Color tc = text;
  g->SetFontSize(res->m_Typefaces, DEFAULT_FONT_SIZE);
  g->DrawText(title, res->m_Typefaces, x + 16, y + 8, tc, tc);
  if (!subtitle.empty()) {
    g->SetFontSize(res->m_Typefaces, SUBTEXT_FONT_SIZE);
    Color subC = {0xCC, 0xDD, 0xFF, 0xFF};
    g->DrawText(subtitle, res->m_Typefaces, x + 16, y + h - 32, subC, subC);
  }
}

void SettingsView::RenderMainList() {
  const int h = m_App->Graph->GetScreenHeight();
  const int w = m_App->Graph->GetScreenWidth();
  Color bg = {0x08, 0x12, 0x20, 0xFF};
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color text = {0xEE, 0xEE, 0xEE, 0xFF};
  Color active = {0x28, 0x58, 0x88, 0xFF};
  Color inactive = {0x14, 0x22, 0x36, 0xFF};
  Color dim = {0x88, 0x88, 0x88, 0xFF};

  m_App->Graph->DrawRectangle(0, 0, w, h, bg);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);
  m_App->Graph->DrawText("Settings", m_App->Res->m_Typefaces, BORDER_X, 48, titleC, titleC);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, SUBTEXT_FONT_SIZE);
  m_App->Graph->DrawText("Cross opens option list for each setting", m_App->Res->m_Typefaces, BORDER_X, 110, dim, dim);

  const int menuX = BORDER_X;
  const int menuY = HEADER_SIZE + 20;
  const int menuW = w - (BORDER_X * 2);
  const int rowH = 72;
  const int page = MENU_NBR_PER_PAGE;
  const int delta = m_MainSelected / page;
  const int maxPage = (MainItemCount() + page - 1) / page;

  for (int row = 0; row < page; row++) {
    const int idx = delta * page + row;
    if (idx >= MainItemCount()) {
      break;
    }
    const MenuItem &item = m_MainItems[static_cast<size_t>(idx)];
    if (item.title == "---") {
      continue;
    }
    const int y = menuY + row * (rowH + MENU_BORDER);
    const bool sel = (idx == m_MainSelected);
    std::string sub = item.subtitle;
    if (item.selectable && item.kind != SettingKind::Info && sel) {
      sub = std::string("Current: ") + item.subtitle + "  —  Cross to pick";
    }
    drawMenuRow(m_App->Graph, m_App->Res, menuX, y, menuW, rowH, item.title, sub, sel, text, active, inactive);
  }

  std::string pageStr;
  Utility::StrSprintf(pageStr, "Page %d / %d", delta + 1, std::max(1, maxPage));
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, FOOTER_FONT_SIZE);
  m_App->Graph->DrawText(pageStr, m_App->Res->m_Typefaces, w - BORDER_X - 200, h - FOOTER_SIZE - 10, dim, dim);

  if (!m_Status.empty()) {
    Color hi = {0x44, 0xFF, 0xAA, 0xFF};
    m_App->Graph->DrawText(m_Status, m_App->Res->m_Typefaces, BORDER_X, h - 130, hi, hi);
  }

  m_App->Graph->DrawText("Up/Down  Cross  Circle back", m_App->Res->m_Typefaces, BORDER_X, h - 50, dim, dim);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
}

void SettingsView::RenderPickerList() {
  const int h = m_App->Graph->GetScreenHeight();
  const int w = m_App->Graph->GetScreenWidth();
  Color bg = {0x06, 0x10, 0x1C, 0xFF};
  Color titleC = {0xFF, 0xFF, 0xFF, 0xFF};
  Color text = {0xEE, 0xEE, 0xEE, 0xFF};
  Color active = {0x2A, 0x6A, 0x48, 0xFF};
  Color inactive = {0x12, 0x28, 0x20, 0xFF};
  Color dim = {0x88, 0x88, 0x88, 0xFF};

  m_App->Graph->DrawRectangle(0, 0, w, h, bg);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, HEADER_FONT_SIZE);
  m_App->Graph->DrawText(m_PickerTitle, m_App->Res->m_Typefaces, BORDER_X, 48, titleC, titleC);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, SUBTEXT_FONT_SIZE);
  m_App->Graph->DrawText("Pick one option", m_App->Res->m_Typefaces, BORDER_X, 110, dim, dim);

  const int menuX = BORDER_X;
  const int menuY = HEADER_SIZE + 30;
  const int menuW = w - (BORDER_X * 2);
  const int rowH = 64;

  for (size_t i = 0; i < m_PickerLabels.size(); i++) {
    const int y = menuY + static_cast<int>(i) * (rowH + MENU_BORDER);
    const bool sel = (static_cast<int>(i) == m_PickerSelected);
    std::string mark = sel ? "> " : "  ";
    drawMenuRow(m_App->Graph, m_App->Res, menuX, y, menuW, rowH, mark + m_PickerLabels[i], "", sel, text, active,
                inactive);
  }

  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, FOOTER_FONT_SIZE);
  m_App->Graph->DrawText("Cross confirm   Circle cancel", m_App->Res->m_Typefaces, BORDER_X, h - 50, dim, dim);
  m_App->Graph->SetFontSize(m_App->Res->m_Typefaces, DEFAULT_FONT_SIZE);
}

int SettingsView::Render() {
  if (m_Screen == SettingsScreen::Picker) {
    RenderPickerList();
  } else {
    RenderMainList();
  }
  return 0;
}
