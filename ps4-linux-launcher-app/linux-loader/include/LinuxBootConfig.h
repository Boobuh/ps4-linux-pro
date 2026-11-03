#ifndef LINUX_BOOT_CONFIG_H
#define LINUX_BOOT_CONFIG_H

#include <string>

#include "PlatformDetect.h"

enum class PayloadProfile { Auto, ProBaikal1Gb, Generic1024Mb };
enum class InstallTarget { InternalHdd, UsbStick };

struct LinuxBootConfig {
  int vramMb = 1024;
  PayloadProfile payload = PayloadProfile::Auto;
  InstallTarget installTarget = InstallTarget::InternalHdd;
  int archGb = 50;
  bool verboseBoot = true;
  SouthbridgeKind southbridgeOverride = SouthbridgeKind::Unknown;

  static constexpr const char *kConfigPath = "/data/linux/boot/ps4-linux-config.json";

  void Load();
  bool Save() const;
  bool WriteBootFiles() const;
  std::string ResolvePayloadPath() const;
  std::string BuildBootargs() const;
  std::string PayloadProfileLabel() const;
  std::string InstallTargetLabel() const;
};

#endif
