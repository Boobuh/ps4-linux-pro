#ifndef LINUX_LOADER_VIEW_H
#define LINUX_LOADER_VIEW_H

#include <cstdint>
#include <string>

#include "LinuxBootConfig.h"
#include "LinuxInstallDetect.h"
#include "PlatformDetect.h"
#include "View.h"

class Application;

class LinuxLoaderView : public View {
public:
  explicit LinuxLoaderView(Application *p_App);
  ~LinuxLoaderView() = default;

  int Update(void) override;
  int Render(void) override;

private:
  Application *m_App;
  LinuxBootConfig m_Config;
  LinuxInstallState m_Install;
  PlatformInfo m_Platform;
  std::string m_PayloadPath;
  std::string m_StatusLine;
  std::string m_BootCheckLine;
  std::string m_HardwareLine;
  bool m_Launching;
  bool m_BootInProgress;
  bool m_LaunchBlockUi;
  bool m_LaunchFailed;
  std::string m_LaunchPhaseLine;
  uint64_t m_LastLaunchTime;
  uint64_t m_LaunchBlockStart;
  int m_MenuIndex;

  enum class SubScreen { None, PickInstallGb, PickVram, AdjustInstallGb, ConfirmReinstall };
  enum class MainMenuAction { PrimaryLaunch, NewInstallWipe, InstallGb, Vram, Refresh };
  SubScreen m_SubScreen;
  int m_PickerSelected;
  int m_ManualArchGb;
  void RefreshPaths();
  void PersistConfigChoice(const char *what);
  int UpdateSubScreen();
  int RenderSubScreen();
  void OpenInstallGbPicker();
  void OpenVramPicker();
  int MainMenuCount() const;
  MainMenuAction ActionForMenuIndex(int index) const;
  void BuildMenuLine(int index, bool selected, std::string &outLine) const;
  void BeginLaunchBlockUi(const char *phaseLine);
  void EndLaunchBlockUiFailed(const char *detail);
  float LaunchProgress01() const;
  int RenderLaunchBlockUi();
  bool LaunchLinuxPayload(bool wipeForNewInstall);
};

#endif
