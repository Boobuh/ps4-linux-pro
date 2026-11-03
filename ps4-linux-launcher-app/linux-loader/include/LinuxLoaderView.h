#ifndef LINUX_LOADER_VIEW_H
#define LINUX_LOADER_VIEW_H

#include <cstdint>
#include <string>

#include "LinuxBootConfig.h"
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
  PlatformInfo m_Platform;
  std::string m_PayloadPath;
  std::string m_StatusLine;
  std::string m_BootCheckLine;
  std::string m_HardwareLine;
  bool m_Launching;
  bool m_BootInProgress;
  uint64_t m_LastLaunchTime;

  void RefreshPaths();
  bool LaunchLinuxPayload();
};

#endif
