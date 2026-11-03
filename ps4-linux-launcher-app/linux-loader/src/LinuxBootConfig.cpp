#include "LinuxBootConfig.h"

#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <string>

#include "Utility.h"
#include "nlohmann_json.hpp"

#include "AppFileLog.h"

static bool pathReadable(const char *p) { return p != nullptr && access(p, R_OK) == 0; }

void LinuxBootConfig::Load() {
  std::string raw;
  if (!Utility::ReadTextFile(kConfigPath, raw)) {
    return;
  }
  nlohmann::json j = nlohmann::json::parse(raw, nullptr, false, true);
  if (j.is_discarded() || !j.is_object()) {
    APP_LOG_ERROR("LinuxBootConfig::Load malformed JSON at %s", kConfigPath);
    return;
  }
  if (j.contains("vram_mb")) {
    vramMb = j["vram_mb"].get<int>();
  }
  if (j.contains("arch_gb")) {
    archGb = j["arch_gb"].get<int>();
  }
  if (j.contains("verbose_boot")) {
    verboseBoot = j["verbose_boot"].get<bool>();
  }
  if (j.contains("payload")) {
    const std::string p = j["payload"].get<std::string>();
    if (p == "pro_baikal_1gb") {
      payload = PayloadProfile::ProBaikal1Gb;
    } else if (p == "generic_1024") {
      payload = PayloadProfile::Generic1024Mb;
    } else {
      payload = PayloadProfile::Auto;
    }
  }
  if (j.contains("install_target")) {
    const std::string t = j["install_target"].get<std::string>();
    installTarget = (t == "usb") ? InstallTarget::UsbStick : InstallTarget::InternalHdd;
  }
}

bool LinuxBootConfig::Save() const {
  nlohmann::json j;
  j["vram_mb"] = vramMb;
  j["arch_gb"] = archGb;
  j["verbose_boot"] = verboseBoot;
  switch (payload) {
  case PayloadProfile::ProBaikal1Gb:
    j["payload"] = "pro_baikal_1gb";
    break;
  case PayloadProfile::Generic1024Mb:
    j["payload"] = "generic_1024";
    break;
  default:
    j["payload"] = "auto";
    break;
  }
  j["install_target"] = (installTarget == InstallTarget::UsbStick) ? "usb" : "internal_hdd";
  if (!Utility::WriteTextFile(kConfigPath, j.dump(2))) {
    APP_LOG_ERRNO("LinuxBootConfig::Save", errno);
    APP_LOG_ERROR("path=%s", kConfigPath);
    return false;
  }
  return true;
}

std::string LinuxBootConfig::PayloadProfileLabel() const {
  switch (payload) {
  case PayloadProfile::ProBaikal1Gb:
    return "Pro Baikal 1GB";
  case PayloadProfile::Generic1024Mb:
    return "Generic 1024MB";
  default:
    return "Auto (best for board)";
  }
}

std::string LinuxBootConfig::InstallTargetLabel() const {
  return (installTarget == InstallTarget::UsbStick) ? "USB stick (not synced)" : "Internal HDD";
}

std::string LinuxBootConfig::ResolvePayloadPath() const {
  auto pick = [](const char *a, const char *b, const char *c, const char *d) -> std::string {
    if (pathReadable(a)) {
      return a;
    }
    if (pathReadable(b)) {
      return b;
    }
    if (pathReadable(c)) {
      return c;
    }
    if (pathReadable(d)) {
      return d;
    }
    return {};
  };

  PayloadProfile use = payload;
  if (use == PayloadProfile::Auto) {
    use = PayloadProfile::Generic1024Mb;
  }

  if (use == PayloadProfile::ProBaikal1Gb) {
    return pick("/data/payloads/payload-1100-1gb-pro-baikal.bin", "/data/payloads/linux-1gb-pro-baikal.bin",
                "/data/payloads/linux-1024mb.elf", "/data/payloads/linux-1024mb.bin");
  }
  return pick("/data/payloads/linux-1024mb.elf", "/data/payloads/linux-1024mb.bin",
              "/data/payloads/payload-1100-1gb-pro-baikal.bin", "/data/payloads/linux-1gb-pro-baikal.bin");
}

std::string LinuxBootConfig::BuildBootargs() const {
  std::string line =
      "panic=0 console=tty0 consoleblank=0 net.ifnames=0 rdinit=/init enforcing=0 video=HDMI-A-1:1920x1080@60 "
      "fbcon=nodefer";
  if (verboseBoot) {
    line += " loglevel=7 ignore_loglevel earlyprintk";
  } else {
    line += " quiet loglevel=3";
  }
  return line;
}

bool LinuxBootConfig::WriteBootFiles() const {
  std::string vram;
  Utility::StrSprintf(vram, "%d\n", vramMb);
  std::string gb;
  Utility::StrSprintf(gb, "%d\n", archGb);
  const std::string bootargs = BuildBootargs();
  if (!Utility::WriteTextFile("/data/linux/boot/vram.txt", vram)) {
    APP_LOG_ERRNO("WriteBootFiles vram.txt", errno);
    return false;
  }
  if (!Utility::WriteTextFile("/data/linux/boot/bootargs.txt", bootargs)) {
    APP_LOG_ERRNO("WriteBootFiles bootargs.txt", errno);
    return false;
  }
  if (installTarget == InstallTarget::InternalHdd) {
    if (!Utility::WriteTextFile("/user/system/boot/ps4-install-gb.txt", gb)) {
      APP_LOG_ERRNO("WriteBootFiles ps4-install-gb.txt", errno);
      return false;
    }
  }
  if (!Save()) {
    return false;
  }
  APP_LOG_INFO("WriteBootFiles OK vram=%d arch_gb=%d verbose=%d", vramMb, archGb, verboseBoot ? 1 : 0);
  return true;
}
