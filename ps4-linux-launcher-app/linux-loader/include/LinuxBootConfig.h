#ifndef LINUX_BOOT_CONFIG_H
#define LINUX_BOOT_CONFIG_H

#include <string>

#include "PlatformDetect.h"

enum class PayloadProfile { Auto, ProBaikal1Gb, Generic1024Mb };
enum class InstallTarget { InternalHdd, UsbStick };

struct LinuxBootConfig {
  static constexpr int kArchGbMin = 50;
  static constexpr int kArchGbDefault = 100;
  static constexpr int kArchGbMax = 512;

  int vramMb = 1024;
  PayloadProfile payload = PayloadProfile::Auto;
  InstallTarget installTarget = InstallTarget::InternalHdd;
  int archGb = kArchGbDefault;
  bool verboseBoot = true;
  SouthbridgeKind southbridgeOverride = SouthbridgeKind::Unknown;

  static constexpr const char *kConfigPath = "/data/linux/boot/ps4-linux-config.json";

  static int ClampArchGb(int gb);
  void Normalize();
  void Load();
  bool Save() const;
  /// `boot` | `install` | `reinstall` — read by initramfs / install-HDD.
  bool WriteLaunchIntent(const char *intent) const;
  bool WriteBootFiles() const;
  std::string ResolvePayloadPath() const;
  std::string BuildBootargs() const;
  std::string PayloadProfileLabel() const;
  std::string InstallTargetLabel() const;
};

#endif
