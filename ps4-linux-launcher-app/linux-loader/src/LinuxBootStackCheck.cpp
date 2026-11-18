#include "LinuxBootStackCheck.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>

#include "KernelCatalog.h"
#include "Utility.h"

namespace {

static constexpr int64_t kKernelMinBytes = 8'000'000;
static constexpr int64_t kInitramfsMinBytes = 3'000'000;

static bool fileStat(const char *path, int64_t *outBytes) {
  if (path == nullptr || access(path, R_OK) != 0) {
    return false;
  }
  struct stat st {};
  if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
    return false;
  }
  if (outBytes != nullptr) {
    *outBytes = static_cast<int64_t>(st.st_size);
  }
  return true;
}

static bool kernelBytesValid(int64_t bytes) {
  if (bytes < kKernelMinBytes) {
    return false;
  }
  for (int i = 0; i < KernelCatalog::Count(); i++) {
    const KernelCatalogEntry &e = KernelCatalog::Entry(i);
    if (e.expectedBytes > 0 && bytes == e.expectedBytes) {
      return true;
    }
    if (bytes >= e.minBytes && bytes <= e.maxBytes) {
      return true;
    }
  }
  return bytes >= kKernelMinBytes && bytes <= 16'000'000;
}

} // namespace

BootStackStatus InspectBootStack() {
  BootStackStatus s;
  s.kernelPresent = fileStat(BootStackStatus::kBzImagePath, &s.kernelBytes);
  s.kernelSizeOk = s.kernelPresent && kernelBytesValid(s.kernelBytes);
  s.initramfsPresent = fileStat(BootStackStatus::kInitramfsPath, &s.initramfsBytes);
  s.initramfsSizeOk = s.initramfsPresent && s.initramfsBytes >= kInitramfsMinBytes;

  std::string idRaw;
  if (Utility::ReadTextFile(BootStackStatus::kKernelIdPath, idRaw)) {
    while (!idRaw.empty() && (idRaw.back() == '\n' || idRaw.back() == '\r' || idRaw.back() == ' ')) {
      idRaw.pop_back();
    }
    s.kernelId = idRaw;
  }
  return s;
}

std::string BootStackStatus::StatusLine() const {
  char buf[256];
  if (ReadyForLaunch()) {
    if (!kernelId.empty()) {
      std::snprintf(buf, sizeof(buf), "Boot stack OK — kernel %lld B (%s), initramfs %lld B", static_cast<long long>(kernelBytes),
                    kernelId.c_str(), static_cast<long long>(initramfsBytes));
    } else {
      std::snprintf(buf, sizeof(buf), "Boot stack OK — bzImage %lld B, initramfs %lld B", static_cast<long long>(kernelBytes),
                    static_cast<long long>(initramfsBytes));
    }
    return buf;
  }
  if (!kernelPresent) {
    return "Kernel missing — Download kernel menu or Mac sync → /data/linux/boot/bzImage";
  }
  if (!kernelSizeOk) {
    std::snprintf(buf, sizeof(buf), "Kernel bad size %lld B — re-download bzImage", static_cast<long long>(kernelBytes));
    return buf;
  }
  if (!initramfsPresent) {
    return "initramfs missing — Mac sync → /data/linux/boot/initramfs.cpio.gz";
  }
  if (!initramfsSizeOk) {
    std::snprintf(buf, sizeof(buf), "initramfs too small (%lld B) — re-run Mac sync", static_cast<long long>(initramfsBytes));
    return buf;
  }
  return "Boot stack incomplete";
}

std::string BootStackStatus::LaunchBlockReason() const {
  if (ReadyForLaunch()) {
    return {};
  }
  return StatusLine();
}