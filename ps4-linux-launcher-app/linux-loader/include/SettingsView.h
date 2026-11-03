#ifndef SETTINGS_VIEW_H
#define SETTINGS_VIEW_H

#include <string>
#include <vector>

#include "LinuxBootConfig.h"
#include "PlatformDetect.h"
#include "View.h"

class Application;

enum class SettingsScreen { Main, Picker };

enum class SettingKind {
  Info,
  Vram,
  Payload,
  InstallTarget,
  ArchGb,
  VerboseBoot,
  ApplyRecommended,
  SaveBootFiles,
  RedetectHardware,
};

class SettingsView : public View {
public:
  SettingsView(Application *p_App, View *p_ReturnView);
  ~SettingsView() = default;

  int Update(void) override;
  int Render(void) override;

private:
  Application *m_App;
  View *m_ReturnView;
  PlatformInfo m_Platform;
  LinuxBootConfig m_Config;
  SettingsScreen m_Screen;
  int m_MainSelected;
  int m_PickerSelected;
  SettingKind m_PickerKind;
  std::vector<std::string> m_PickerLabels;
  std::string m_Status;
  std::string m_PickerTitle;

  struct MenuItem {
    std::string title;
    std::string subtitle;
    SettingKind kind;
    bool selectable;
  };

  std::vector<MenuItem> m_MainItems;

  void RebuildMainMenu();
  void OpenPicker(SettingKind kind);
  void ApplyPickerChoice(int index);
  void ApplyRecommended();
  void SaveBootFiles();
  void RenderMainList();
  void RenderPickerList();
  int MainItemCount() const;
};

#endif
