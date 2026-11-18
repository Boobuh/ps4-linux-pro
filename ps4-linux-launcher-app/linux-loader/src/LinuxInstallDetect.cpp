#include "LinuxInstallDetect.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "AppFileLog.h"
#include "Utility.h"

static constexpr const char *kArchImgPath = "/user/home/Arch.img";
static constexpr const char *kInstallMetaPath = "/user/system/boot/ps4-linux-installed.meta";
static constexpr const char *kInstallStatusPath = "/user/system/boot/install-status.txt";
static constexpr int64_t kOneGb = 1024LL * 1024LL * 1024LL;

static bool fileExists(const char *path) { return path != nullptr && access(path, R_OK) == 0; }

static int64_t fileSizeBytes(const char *path) {
  struct stat st {};
  if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
    return -1;
  }
  return static_cast<int64_t>(st.st_size);
}

static bool readMetaField(const std::string &raw, const char *key, std::string *out) {
  const std::string needle = std::string(key) + "=";
  const size_t pos = raw.find(needle);
  if (pos == std::string::npos) {
    return false;
  }
  size_t start = pos + needle.size();
  size_t end = raw.find('\n', start);
  if (end == std::string::npos) {
    end = raw.size();
  }
  *out = raw.substr(start, end - start);
  return !out->empty();
}

static bool installStatusIndicatesComplete(const std::string &status) {
  return status.find("Step 3/3 done") != std::string::npos ||
         status.find("extract finished") != std::string::npos ||
         status.find("switch_root") != std::string::npos;
}

LinuxInstallState DetectLinuxInstallOnHdd() {
  LinuxInstallState out;

  const int64_t archBytes = fileSizeBytes(kArchImgPath);
  if (archBytes < 0) {
    out.summaryLine = "No Linux on internal HDD (Arch.img missing)";
    return out;
  }

  out.archImgSizeGb = static_cast<int>((archBytes + kOneGb - 1) / kOneGb);
  if (archBytes < 256LL * 1024LL * 1024LL) {
    out.level = LinuxInstallLevel::Partial;
    out.summaryLine = "Partial Linux install (Arch.img too small — use Setup new)";
    return out;
  }

  std::string meta;
  if (Utility::ReadTextFile(kInstallMetaPath, meta)) {
    (void)readMetaField(meta, "distro", &out.distro);
    std::string gbStr;
    if (readMetaField(meta, "arch_gb", &gbStr)) {
      out.metaArchGb = std::atoi(gbStr.c_str());
    }
    std::string complete;
    if (readMetaField(meta, "install_complete", &complete) && complete == "1") {
      out.level = LinuxInstallLevel::Ready;
    }
  }

  std::string status;
  if (Utility::ReadTextFile(kInstallStatusPath, status) && installStatusIndicatesComplete(status)) {
    out.level = LinuxInstallLevel::Ready;
  }

  if (out.level != LinuxInstallLevel::Ready && out.archImgSizeGb >= 50) {
    out.level = LinuxInstallLevel::Ready;
    APP_LOG_INFO("Install detect: Arch.img %d GB, no meta — treating as installed", out.archImgSizeGb);
  }

  if (out.level != LinuxInstallLevel::Ready) {
    out.level = LinuxInstallLevel::Partial;
    out.summaryLine = "Partial Linux install — use Setup new to wipe and retry";
    return out;
  }

  const int showGb = (out.metaArchGb > 0) ? out.metaArchGb : out.archImgSizeGb;
  const char *distro = out.distro.empty() ? "psxitarch" : out.distro.c_str();
  char buf[160];
  std::snprintf(buf, sizeof(buf), "Installed: %s on internal HDD (%d GB partition)", distro, showGb);
  out.summaryLine = buf;
  return out;
}

bool WipeLinuxInstallForReinstall() {
  static const char *kPaths[] = {kArchImgPath, kInstallStatusPath, kInstallMetaPath};
  bool any = false;
  for (const char *path : kPaths) {
    if (!fileExists(path)) {
      continue;
    }
    if (std::remove(path) == 0) {
      APP_LOG_INFO("WipeLinuxInstall: removed %s", path);
      any = true;
    } else {
      APP_LOG_ERRNO("WipeLinuxInstall remove", errno);
      return false;
    }
  }
  if (!any) {
    APP_LOG_INFO("WipeLinuxInstall: nothing to remove (fresh install)");
  }
  return true;
}
