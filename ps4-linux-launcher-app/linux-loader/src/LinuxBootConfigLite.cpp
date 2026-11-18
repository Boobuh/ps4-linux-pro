// Slim LinuxBootConfig for ship eboot (no nlohmann — keeps CSTP00003 under OneFamily FSELF ceiling).
#include "LinuxBootConfig.h"

#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>

#include "AppFileLog.h"
#include "Ps4NetworkInherit.h"
#include "Utility.h"

static bool pathReadable(const char *p) { return p != nullptr && access(p, R_OK) == 0; }

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

static bool readIntField(const std::string &raw, const char *key, int *out) {
  const std::string needle = std::string("\"") + key + "\":";
  const size_t pos = raw.find(needle);
  if (pos == std::string::npos) {
    return false;
  }
  const char *p = raw.c_str() + pos + needle.size();
  while (*p == ' ' || *p == '\t') {
    p++;
  }
  return std::sscanf(p, "%d", out) == 1;
}

static bool readBoolField(const std::string &raw, const char *key, bool *out) {
  const std::string needle = std::string("\"") + key + "\":";
  const size_t pos = raw.find(needle);
  if (pos == std::string::npos) {
    return false;
  }
  const char *p = raw.c_str() + pos + needle.size();
  while (*p == ' ' || *p == '\t') {
    p++;
  }
  if (std::strncmp(p, "true", 4) == 0) {
    *out = true;
    return true;
  }
  if (std::strncmp(p, "false", 5) == 0) {
    *out = false;
    return true;
  }
  return false;
}

static bool readQuotedField(const std::string &raw, const char *key, std::string *out) {
  const std::string needle = std::string("\"") + key + "\":";
  const size_t pos = raw.find(needle);
  if (pos == std::string::npos) {
    return false;
  }
  const size_t q = raw.find('"', pos + needle.size());
  if (q == std::string::npos) {
    return false;
  }
  const size_t q2 = raw.find('"', q + 1);
  if (q2 == std::string::npos) {
    return false;
  }
  *out = raw.substr(q + 1, q2 - q - 1);
  return true;
}

void LinuxBootConfig::Load() {
  std::string raw;
  if (!Utility::ReadTextFile(kConfigPath, raw)) {
    return;
  }
  (void)readIntField(raw, "vram_mb", &vramMb);
  (void)readIntField(raw, "arch_gb", &archGb);
  (void)readBoolField(raw, "verbose_boot", &verboseBoot);
  std::string payloadStr;
  if (readQuotedField(raw, "payload", &payloadStr)) {
    if (payloadStr == "pro_baikal_1gb") {
      payload = PayloadProfile::ProBaikal1Gb;
    } else if (payloadStr == "generic_1024") {
      payload = PayloadProfile::Generic1024Mb;
    } else {
      payload = PayloadProfile::Auto;
    }
  }
  std::string targetStr;
  if (readQuotedField(raw, "install_target", &targetStr)) {
    installTarget = (targetStr == "usb") ? InstallTarget::UsbStick : InstallTarget::InternalHdd;
  }
  Normalize();
}

bool LinuxBootConfig::Save() const {
  const char *payloadStr = "auto";
  switch (payload) {
  case PayloadProfile::ProBaikal1Gb:
    payloadStr = "pro_baikal_1gb";
    break;
  case PayloadProfile::Generic1024Mb:
    payloadStr = "generic_1024";
    break;
  default:
    break;
  }
  const char *targetStr = (installTarget == InstallTarget::UsbStick) ? "usb" : "internal_hdd";
  char buf[512];
  const int n = std::snprintf(buf, sizeof(buf),
                              "{\n  \"vram_mb\": %d,\n  \"arch_gb\": %d,\n  \"verbose_boot\": %s,\n  "
                              "\"payload\": \"%s\",\n  \"install_target\": \"%s\"\n}\n",
                              vramMb, archGb, verboseBoot ? "true" : "false", payloadStr, targetStr);
  if (n <= 0 || static_cast<size_t>(n) >= sizeof(buf)) {
    return false;
  }
  if (!Utility::WriteTextFile(kConfigPath, std::string(buf))) {
    APP_LOG_ERRNO("LinuxBootConfig::Save", errno);
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
  if (!Save()) {
    return false;
  }
  APP_LOG_INFO("WriteBootFiles OK vram=%d arch_gb=%d verbose=%d", vramMb, archGb, verboseBoot ? 1 : 0);
  return true;
}
