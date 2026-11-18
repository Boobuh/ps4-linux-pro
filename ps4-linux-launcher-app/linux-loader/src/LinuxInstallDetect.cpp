#include "LinuxInstallDetect.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "AppFileLog.h"
#include "Utility.h"

namespace {

static constexpr const char *kArchImgPaths[] = {
    "/user/home/Arch.img",
};

static constexpr const char *kInstallMetaPaths[] = {
    "/user/system/boot/ps4-linux-installed.meta",
    "/data/linux/boot/ps4-linux-installed.meta",
};

static constexpr const char *kInstallStatusPaths[] = {
    "/user/system/boot/install-status.txt",
    "/data/linux/boot/install-status.txt",
};

static constexpr int64_t kOneGb = 1024LL * 1024LL * 1024LL;
static constexpr int64_t kMinPartialBytes = 256LL * 1024LL * 1024LL;

bool fileExists(const char *path) { return path != nullptr && access(path, R_OK) == 0; }

int64_t fileSizeBytes(const char *path) {
  struct stat st {};
  if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
    return -1;
  }
  return static_cast<int64_t>(st.st_size);
}

bool readMetaField(const std::string &raw, const char *key, std::string *out) {
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

bool installStatusIndicatesComplete(const std::string &status) {
  return status.find("Step 3/3 done") != std::string::npos ||
         status.find("extract finished") != std::string::npos ||
         status.find("switch_root") != std::string::npos ||
         status.find("install_complete=1") != std::string::npos;
}

const char *resolveArchImgPath(int64_t *outBytes) {
  for (const char *path : kArchImgPaths) {
    const int64_t bytes = fileSizeBytes(path);
    if (bytes >= 0) {
      if (outBytes != nullptr) {
        *outBytes = bytes;
      }
      return path;
    }
  }
  if (outBytes != nullptr) {
    *outBytes = -1;
  }
  return nullptr;
}

bool readFirstExistingText(const char *const *paths, size_t count, std::string *out) {
  for (size_t i = 0; i < count; i++) {
    if (Utility::ReadTextFile(paths[i], *out)) {
      return true;
    }
  }
  out->clear();
  return false;
}

void mirrorInstallMeta(const LinuxInstallState &state) {
  if (!state.IsReady()) {
    return;
  }
  if (fileExists(kInstallMetaPaths[0]) || fileExists(kInstallMetaPaths[1])) {
    return;
  }
  const int gb = state.metaArchGb > 0 ? state.metaArchGb : state.archImgSizeGb;
  const char *distro = state.distro.empty() ? "psxitarch" : state.distro.c_str();
  char meta[192];
  std::snprintf(meta, sizeof(meta), "distro=%s\narch_gb=%d\ninstall_complete=1\n", distro, gb);
  const std::string body(meta);
  for (const char *path : kInstallMetaPaths) {
    if (Utility::WriteTextFile(path, body)) {
      APP_LOG_INFO("Install detect: mirrored meta to %s", path);
    }
  }
}

} // namespace

LinuxInstallState DetectLinuxInstallOnHdd() {
  LinuxInstallState out;

  int64_t archBytes = -1;
  const char *archPath = resolveArchImgPath(&archBytes);
  if (archPath == nullptr || archBytes < 0) {
    out.summaryLine = "No Linux on internal HDD (Arch.img missing)";
    return out;
  }
  out.archImgPath = archPath;

  out.archImgSizeGb = static_cast<int>((archBytes + kOneGb - 1) / kOneGb);
  if (archBytes < kMinPartialBytes) {
    out.level = LinuxInstallLevel::Partial;
    out.summaryLine = "Partial Linux install (Arch.img too small — use Setup new)";
    return out;
  }

  std::string meta;
  if (readFirstExistingText(kInstallMetaPaths, sizeof(kInstallMetaPaths) / sizeof(kInstallMetaPaths[0]), &meta)) {
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
  if (readFirstExistingText(kInstallStatusPaths, sizeof(kInstallStatusPaths) / sizeof(kInstallStatusPaths[0]),
                            &status) &&
      installStatusIndicatesComplete(status)) {
    out.level = LinuxInstallLevel::Ready;
  }

  if (out.level != LinuxInstallLevel::Ready && out.archImgSizeGb >= 50) {
    out.level = LinuxInstallLevel::Ready;
    APP_LOG_INFO("Install detect: %s %d GB, no meta — treating as installed", archPath, out.archImgSizeGb);
  }

  if (out.level != LinuxInstallLevel::Ready) {
    out.level = LinuxInstallLevel::Partial;
    out.summaryLine = "Partial Linux install — use Setup new to wipe and retry";
    return out;
  }

  mirrorInstallMeta(out);

  const int showGb = (out.metaArchGb > 0) ? out.metaArchGb : out.archImgSizeGb;
  const char *distro = out.distro.empty() ? "psxitarch" : out.distro.c_str();
  char buf[192];
  std::snprintf(buf, sizeof(buf), "Installed: %s on internal HDD (%d GB) — ready to boot", distro, showGb);
  out.summaryLine = buf;
  return out;
}

bool WipeLinuxInstallForReinstall() {
  static const char *kPaths[] = {
      "/user/home/Arch.img",
      "/user/system/boot/install-status.txt",
      "/user/system/boot/ps4-linux-installed.meta",
      "/data/linux/boot/install-status.txt",
      "/data/linux/boot/ps4-linux-installed.meta",
      "/data/linux/boot/ps4-linux-launch-intent.txt",
      "/user/system/boot/ps4-linux-launch-intent.txt",
  };
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