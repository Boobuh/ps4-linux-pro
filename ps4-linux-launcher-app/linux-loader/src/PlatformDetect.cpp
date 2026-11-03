#include "PlatformDetect.h"

#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "LinuxBootConfig.h"
#include "Utility.h"

static bool readFileToString(const char *path, std::string &out) {
  out.clear();
  FILE *f = std::fopen(path, "r");
  if (!f) {
    return false;
  }
  char buf[4096];
  size_t n = 0;
  while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    out.append(buf, n);
  }
  std::fclose(f);
  return !out.empty();
}

static void parseSouthbridgeLine(const std::string &line, PlatformInfo &info) {
  const char *sb = std::strstr(line.c_str(), "southbridge=");
  if (!sb) {
    return;
  }
  sb += 12;
  if (std::strncmp(sb, "Baikal", 6) == 0) {
    info.southbridge = SouthbridgeKind::Baikal;
    info.southbridgeName = "Baikal";
  } else if (std::strncmp(sb, "Belize", 6) == 0) {
    info.southbridge = SouthbridgeKind::Belize;
    info.southbridgeName = "Belize";
  } else if (std::strncmp(sb, "Aeolia", 6) == 0) {
    info.southbridge = SouthbridgeKind::Aeolia;
    info.southbridgeName = "Aeolia";
  } else if (std::strncmp(sb, "Livermore", 9) == 0) {
    info.southbridge = SouthbridgeKind::Livermore;
    info.southbridgeName = "Livermore";
  }

  const char *id = std::strchr(sb, '(');
  if (id) {
    const char *end = std::strchr(id, ')');
    if (end && end > id + 1) {
      info.southbridgeId.assign(id + 1, static_cast<size_t>(end - id - 1));
    }
  }
}

static void parseFirmwareLine(const std::string &line, PlatformInfo &info) {
  const char *fw = std::strstr(line.c_str(), "firmware=");
  if (!fw) {
    return;
  }
  fw += 9;
  char major = fw[0];
  char minor = fw[1];
  if (major && minor) {
    Utility::StrSprintf(info.firmwareLine, "Firmware %c.%c.%c", major, minor, fw[2] ? fw[2] : '0');
  }
}

PlatformInfo DetectPlatform() {
  PlatformInfo info;

  const char *logPaths[] = {
      "/user/app/ps4-android/logs/launcher.log",
      "/user/app/ps4-android/logs/launcher.previous.log",
      nullptr,
  };

  for (int i = 0; logPaths[i]; i++) {
    std::string text;
    if (!readFileToString(logPaths[i], text)) {
      continue;
    }
    size_t pos = 0;
    while (pos < text.size()) {
      size_t end = text.find('\n', pos);
      if (end == std::string::npos) {
        end = text.size();
      }
      std::string line = text.substr(pos, end - pos);
      parseSouthbridgeLine(line, info);
      parseFirmwareLine(line, info);
      pos = end + 1;
    }
    if (info.southbridge != SouthbridgeKind::Unknown) {
      info.detectSource = logPaths[i];
      break;
    }
  }

  if (info.firmwareLine == "Unknown FW") {
    info.firmwareLine = "Firmware (see Android TV log or GoldHEN)";
  }

  if (access("/data/payloads/payload-1100-1gb-pro-baikal.bin", R_OK) == 0 &&
      info.southbridge == SouthbridgeKind::Baikal) {
    info.likelyPro = true;
    info.consoleLine = "PS4 Pro (Baikal, Gladius GPU likely)";
  } else if (info.southbridge == SouthbridgeKind::Baikal) {
    info.consoleLine = "PS4 Slim / Pro (Baikal — confirm in Settings)";
  } else if (info.southbridge == SouthbridgeKind::Belize) {
    info.consoleLine = "PS4 Pro (Belize)";
    info.likelyPro = true;
  } else if (info.southbridge == SouthbridgeKind::Aeolia) {
    info.consoleLine = "PS4 Original / Slim (Aeolia)";
  }

  if (info.southbridge == SouthbridgeKind::Unknown &&
      access("/data/payloads/payload-1100-1gb-pro-baikal.bin", R_OK) == 0) {
    info.southbridge = SouthbridgeKind::Baikal;
    info.southbridgeName = "Baikal (inferred)";
    info.likelyPro = true;
    info.consoleLine = "Likely PS4 Pro Baikal (payload heuristic)";
    info.detectSource = "payload-1100-1gb-pro-baikal.bin";
  }

  return info;
}

void ApplyRecommendedDefaults(LinuxBootConfig &cfg, const PlatformInfo &info) {
  cfg.verboseBoot = true;
  cfg.installTarget = InstallTarget::InternalHdd;
  cfg.archGb = 50;
  cfg.vramMb = 1024;
  cfg.payload = PayloadProfile::Auto;

  switch (info.southbridge) {
  case SouthbridgeKind::Baikal:
    cfg.vramMb = 1024;
    cfg.payload = PayloadProfile::Generic1024Mb;
    break;
  case SouthbridgeKind::Belize:
    cfg.vramMb = 1024;
    cfg.payload = PayloadProfile::Generic1024Mb;
    break;
  case SouthbridgeKind::Aeolia:
    cfg.vramMb = 512;
    cfg.payload = PayloadProfile::Generic1024Mb;
    break;
  default:
    break;
  }

  if (info.likelyPro && cfg.vramMb < 1024) {
    cfg.vramMb = 1024;
  }
}
