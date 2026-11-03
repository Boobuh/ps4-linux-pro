#ifndef PLATFORM_DETECT_H
#define PLATFORM_DETECT_H

#include <string>

enum class SouthbridgeKind { Unknown, Aeolia, Belize, Baikal, Livermore };

struct PlatformInfo {
  SouthbridgeKind southbridge = SouthbridgeKind::Unknown;
  std::string southbridgeName = "Unknown";
  std::string southbridgeId;
  std::string consoleLine = "Unknown model";
  std::string firmwareLine = "Unknown FW";
  std::string detectSource = "none";
  bool likelyPro = false;
};

PlatformInfo DetectPlatform();
void ApplyRecommendedDefaults(struct LinuxBootConfig &cfg, const PlatformInfo &info);

#endif
