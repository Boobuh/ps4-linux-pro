#include "LinuxInstallDetect.h"

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>

#include "AppFileLog.h"
#include "Utility.h"

namespace {

static constexpr const char *kArchImgPaths[] = {
    "/user/home/Arch.img",
};

static constexpr const char *kHomeScanDir = "/user/home";

// Homebrew often cannot open /user/home or /user/system/boot — prefer app-writable /data/linux/boot.
static constexpr const char *kInstallMetaPaths[] = {
    "/data/linux/boot/ps4-linux-installed.meta",
    "/user/system/boot/ps4-linux-installed.meta",
};

static constexpr const char *kInstallStatusPaths[] = {
    "/data/linux/boot/install-status.txt",
    "/user/system/boot/install-status.txt",
};

static constexpr int64_t kOneGb = 1024LL * 1024LL * 1024LL;
static constexpr int64_t kMinPartialBytes = 256LL * 1024LL * 1024LL;
static constexpr off_t kExt2MagicOffset = 1024 + 56;

bool fileExists(const char *path) { return path != nullptr && access(path, R_OK) == 0; }

int64_t fileSizeBytes(const char *path) { return Utility::FileSizeBytes(path); }

bool fileHasExt2Superblock(const char *path) {
  if (path == nullptr || path[0] == '\0') {
    return false;
  }
  const int fd = open(path, O_RDONLY);
  if (fd < 0) {
    return false;
  }
  unsigned char magic[2] = {0, 0};
  bool ok = false;
  if (lseek(fd, kExt2MagicOffset, SEEK_SET) == kExt2MagicOffset) {
    if (read(fd, magic, 2) == 2 && magic[0] == 0x53 && magic[1] == 0xEF) {
      ok = true;
    }
  }
  close(fd);
  return ok;
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

bool fillReadyFromMetaStatus(const std::string &meta, const std::string &status, LinuxInstallState *out) {
  if (out == nullptr) {
    return false;
  }
  bool complete = false;
  if (!meta.empty()) {
    std::string completeVal;
    if (readMetaField(meta, "install_complete", &completeVal) && completeVal == "1") {
      complete = true;
    }
    (void)readMetaField(meta, "distro", &out->distro);
    std::string gbStr;
    if (readMetaField(meta, "arch_gb", &gbStr)) {
      out->metaArchGb = std::atoi(gbStr.c_str());
    }
  }
  if (!complete && !status.empty() && installStatusIndicatesComplete(status)) {
    complete = true;
  }
  if (!complete) {
    return false;
  }
  out->level = LinuxInstallLevel::Ready;
  out->archImgPath = kArchImgPaths[0];
  if (out->metaArchGb >= 50) {
    out->archImgSizeGb = out->metaArchGb;
  }
  return true;
}

bool endsWithImg(const char *name) {
  if (name == nullptr) {
    return false;
  }
  const size_t len = std::strlen(name);
  return len >= 4 && std::strcmp(name + len - 4, ".img") == 0;
}

bool resolveArchImgPath(std::string *outPath, int64_t *outBytes) {
  int64_t bestBytes = -1;
  std::string best;

  for (const char *path : kArchImgPaths) {
    const int64_t bytes = fileSizeBytes(path);
    if (bytes >= 0 && bytes > bestBytes) {
      bestBytes = bytes;
      best = path;
    }
  }

  DIR *dir = opendir(kHomeScanDir);
  if (dir != nullptr) {
    struct dirent *ent = nullptr;
    while ((ent = readdir(dir)) != nullptr) {
      if (ent->d_name[0] == '.' || !endsWithImg(ent->d_name)) {
        continue;
      }
      char path[320];
      std::snprintf(path, sizeof(path), "%s/%s", kHomeScanDir, ent->d_name);
      const int64_t bytes = fileSizeBytes(path);
      if (bytes >= 0 && bytes > bestBytes) {
        bestBytes = bytes;
        best = path;
      }
    }
    closedir(dir);
  }

  if (bestBytes < 0 || best.empty()) {
    if (outBytes != nullptr) {
      *outBytes = -1;
    }
    return false;
  }
  if (outPath != nullptr) {
    *outPath = best;
  }
  if (outBytes != nullptr) {
    *outBytes = bestBytes;
  }
  return true;
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
  std::string archPath;
  if (!resolveArchImgPath(&archPath, &archBytes) || archBytes < 0) {
    std::string meta;
    std::string status;
    const bool hasMeta =
        readFirstExistingText(kInstallMetaPaths, sizeof(kInstallMetaPaths) / sizeof(kInstallMetaPaths[0]), &meta);
    const bool hasStatus = readFirstExistingText(kInstallStatusPaths,
                                                 sizeof(kInstallStatusPaths) / sizeof(kInstallStatusPaths[0]), &status);
    if (fillReadyFromMetaStatus(meta, status, &out)) {
      APP_LOG_INFO("Install detect: ready from /data/linux/boot markers (Arch.img on HDD — app cannot stat /user/home)");
      const int showGb = (out.metaArchGb > 0) ? out.metaArchGb : out.archImgSizeGb;
      const char *distro = out.distro.empty() ? "psxitarch" : out.distro.c_str();
      char buf[240];
      std::snprintf(buf, sizeof(buf),
                    "Linux partition ready: %s on internal HDD (%d GB) — boot OK (image not visible to Orbis app)",
                    distro, showGb > 0 ? showGb : 100);
      out.summaryLine = buf;
      return out;
    }
    if (hasMeta || hasStatus) {
      out.summaryLine = "Install meta on PS4 HDD but Linux partition file missing — run Setup new";
      out.level = LinuxInstallLevel::Partial;
      APP_LOG_WARN("Install detect: incomplete meta/status without Arch.img");
      return out;
    }
    if (access(kArchImgPaths[0], F_OK) == 0) {
      APP_LOG_WARN("Install detect: %s exists but size unreadable (errno %d)", kArchImgPaths[0], errno);
    }
    out.summaryLine = "No Linux partition on PS4 HDD (Arch.img not on /user/home)";
    return out;
  }
  out.archImgPath = archPath;
  out.hasLinuxExt2Partition = fileHasExt2Superblock(archPath.c_str());
  APP_LOG_INFO("Install detect: partition %s %lld B ext2=%d", archPath.c_str(), static_cast<long long>(archBytes),
               out.hasLinuxExt2Partition ? 1 : 0);

  out.archImgSizeGb = static_cast<int>((archBytes + kOneGb - 1) / kOneGb);
  if (archBytes < kMinPartialBytes) {
    out.level = LinuxInstallLevel::Partial;
    out.summaryLine = "Partial Linux partition (image too small — use Setup new)";
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

  if (out.level != LinuxInstallLevel::Ready && out.archImgSizeGb >= 50 && out.hasLinuxExt2Partition) {
    out.level = LinuxInstallLevel::Ready;
    APP_LOG_INFO("Install detect: ext2 Linux partition %d GB — treating as installed", out.archImgSizeGb);
  }

  if (out.level != LinuxInstallLevel::Ready) {
    out.level = LinuxInstallLevel::Partial;
    if (out.hasLinuxExt2Partition) {
      out.summaryLine = "Linux ext2 partition found — finish install or use Boot (not native PS4 storage)";
    } else if (out.archImgSizeGb >= 10) {
      out.summaryLine = "Linux partition file allocated — formatting/install not finished (Setup new to retry)";
    } else {
      out.summaryLine = "Partial Linux partition — use Setup new to wipe and retry";
    }
    return out;
  }

  mirrorInstallMeta(out);

  const int showGb = (out.metaArchGb > 0) ? out.metaArchGb : out.archImgSizeGb;
  const char *distro = out.distro.empty() ? "psxitarch" : out.distro.c_str();
  char buf[224];
  std::snprintf(buf, sizeof(buf),
                "Linux partition ready: %s ext2 in Arch.img (%d GB) — separate from native PS4 — boot OK", distro,
                showGb);
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
  DIR *dir = opendir(kHomeScanDir);
  if (dir != nullptr) {
    struct dirent *ent = nullptr;
    while ((ent = readdir(dir)) != nullptr) {
      if (ent->d_name[0] == '.' || !endsWithImg(ent->d_name)) {
        continue;
      }
      if (std::strcmp(ent->d_name, "Arch.img") == 0) {
        continue;
      }
      char path[320];
      std::snprintf(path, sizeof(path), "%s/%s", kHomeScanDir, ent->d_name);
      if (std::remove(path) == 0) {
        APP_LOG_INFO("WipeLinuxInstall: removed alt partition %s", path);
        any = true;
      }
    }
    closedir(dir);
  }
  if (!any) {
    APP_LOG_INFO("WipeLinuxInstall: nothing to remove (fresh install)");
  }
  return true;
}