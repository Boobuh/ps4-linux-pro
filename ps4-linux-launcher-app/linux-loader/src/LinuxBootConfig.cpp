#if defined(PS4LINUX_BOOT_CONFIG_LITE)
// Built from LinuxBootConfigLite.cpp when PS4LINUX_BOOT_CONFIG_LITE is set.
#else

#include "LinuxBootConfig.h"

#include <unistd.h>

#include <ctime>

#include <cerrno>
#include <cstdio>
#include <string>

#include "Utility.h"
#include "nlohmann_json.hpp"

#include "AppFileLog.h"
#include "Ps4NetworkInherit.h"
#include "Ps4NetworkInherit.h"

static bool pathReadable(const char *p) { return p != nullptr && access(p, R_OK) == 0; }

static bool writeOrbisUtcStamp() {
  const std::time_t now = std::time(nullptr);
  if (now <= 0) {
    return false;
  }
  std::string line;
  Utility::StrSprintf(line, "%lld\n", static_cast<long long>(now));
  bool ok = Utility::WriteTextFile("/data/linux/boot/ps4-linux-orbis-utc.txt", line);
  if (!Utility::WriteTextFile("/user/system/boot/ps4-linux-orbis-utc.txt", line)) {
    APP_LOG_WARN("WriteBootFiles: ps4-linux-orbis-utc not on /user/system/boot");
  } else {
    ok = true;
  }
  return ok;
}

int LinuxBootConfig::ClampArchGb(int gb) {
  if (gb < kArchGbMin) {
    return kArchGbMin;
  }
  if (gb > kArchGbMax) {
    return kArchGbMax;
  }
  return gb;
}

void LinuxBootConfig::Normalize() {
  archGb = ClampArchGb(archGb);
  if (vramMb != 512 && vramMb != 1024 && vramMb != 2048 && vramMb != 4096) {
    vramMb = (vramMb < 768) ? 512 : 1024;
  }
}

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
  Normalize();
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
    return pick("/data/payloads/linux-1024mb.bin", "/data/payloads/payload-1100-1gb-pro-baikal.bin",
                "/data/payloads/linux-1gb-pro-baikal.bin", "/data/payloads/linux-1024mb.elf");
  }
  return pick("/data/payloads/linux-1024mb.bin", "/data/payloads/payload-1100-1gb-pro-baikal.bin",
              "/data/payloads/linux-1gb-pro-baikal.bin", "/data/payloads/linux-1024mb.elf");
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

static bool writeInstallGbOrUseExisting(const std::string &gb) {
  if (Utility::WriteTextFile("/data/linux/boot/ps4-install-gb.txt", gb)) {
    return true;
  }
  if (Utility::WriteTextFile("/user/system/boot/ps4-install-gb.txt", gb)) {
    return true;
  }
  if (pathReadable("/data/linux/boot/ps4-install-gb.txt") ||
      pathReadable("/user/system/boot/ps4-install-gb.txt")) {
    APP_LOG_WARN("WriteBootFiles: ps4-install-gb not writable; using existing file from sync");
    return true;
  }
  APP_LOG_ERRNO("WriteBootFiles ps4-install-gb.txt", errno);
  return false;
}

bool LinuxBootConfig::WriteLaunchIntent(const char *intent) const {
  if (intent == nullptr || intent[0] == '\0') {
    return false;
  }
  std::string line(intent);
  if (line.back() != '\n') {
    line += "\n";
  }
  bool ok = Utility::WriteTextFile("/data/linux/boot/ps4-linux-launch-intent.txt", line);
  ok = Utility::WriteTextFile("/user/system/boot/ps4-linux-launch-intent.txt", line) || ok;
  if (!ok) {
    APP_LOG_WARN("WriteLaunchIntent: could not write ps4-linux-launch-intent.txt");
  } else {
    APP_LOG_INFO("WriteLaunchIntent=%s", intent);
  }
  return ok;
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
  if (installTarget == InstallTarget::InternalHdd && !writeInstallGbOrUseExisting(gb)) {
    return false;
  }
  if (!WritePs4NetworkInheritConf()) {
    APP_LOG_WARN("WriteBootFiles: ps4-net-inherit.conf not written (install netdebug may use DHCP)");
  }
  if (!writeOrbisUtcStamp()) {
    APP_LOG_WARN("WriteBootFiles: ps4-linux-orbis-utc.txt not written (install logs may show 1970)");
  }
  if (!Save()) {
    return false;
  }
  APP_LOG_INFO("WriteBootFiles OK vram=%d arch_gb=%d verbose=%d", vramMb, archGb, verboseBoot ? 1 : 0);
  return true;
}

#endif // !PS4LINUX_BOOT_CONFIG_LITE
