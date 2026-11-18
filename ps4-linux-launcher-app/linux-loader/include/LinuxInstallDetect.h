#ifndef LINUX_INSTALL_DETECT_H
#define LINUX_INSTALL_DETECT_H

#include <cstdint>
#include <string>

enum class LinuxInstallLevel { None, Partial, Ready };

struct LinuxInstallState {
  LinuxInstallLevel level = LinuxInstallLevel::None;
  int archImgSizeGb = 0;
  int metaArchGb = 0;
  std::string distro;
  std::string summaryLine;

  bool IsReady() const { return level == LinuxInstallLevel::Ready; }
  bool IsPartial() const { return level == LinuxInstallLevel::Partial; }
};

LinuxInstallState DetectLinuxInstallOnHdd();
bool WipeLinuxInstallForReinstall();

#endif
