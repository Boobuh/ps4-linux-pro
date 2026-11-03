#include "AppFileLog.h"

#include "BootTrace.h"
#include "BuildVersion.h"

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <ctime>

// Prefer title install dir (writable from app sandbox on GoldHEN).
static const char *kTitleLogPath = "/user/app/CSTP00002/ps4-linux-app.log";
static const char *kUserDotLogPath = "/user/.ps4-linux-app.log";
static const char *kUserDataLogPath = "/user/data/ps4-linux-app.log";
static const char *kPkgDirLogPath = "/data/pkg/ps4-linux-app.log";
static const char *kBootLogPath = "/data/linux/boot/ps4-linux-app.log";
static const char *kSystemBootLogPath = "/user/system/boot/ps4-linux-app.log";
static const char *kFallbackLogPath = "/data/ps4-linux-app.log";
static const char *g_ActiveLogPath = kTitleLogPath;

static void appendLine(const char *level, const char *file, int line, const char *message) {
  const char *paths[] = {g_ActiveLogPath, kTitleLogPath, kUserDotLogPath, kUserDataLogPath, kPkgDirLogPath,
                         kBootLogPath,    kSystemBootLogPath, kFallbackLogPath, nullptr};
  FILE *f = nullptr;
  for (int i = 0; paths[i] != nullptr; i++) {
    f = std::fopen(paths[i], "a");
    if (f) {
      g_ActiveLogPath = paths[i];
      break;
    }
  }
  if (!f) {
    char buf[2200];
    if (file != nullptr && line > 0) {
      std::snprintf(buf, sizeof(buf), "%s %s:%d: %s", level, file, line, message);
    } else {
      std::snprintf(buf, sizeof(buf), "%s %s", level, message);
    }
    bootTrace(buf);
    return;
  }

  char ts[64];
  ts[0] = '\0';
  const std::time_t now = std::time(nullptr);
  if (now > 0) {
    struct tm tm_buf {};
#if defined(_POSIX_THREAD_SAFE_FUNCTIONS) || defined(__FreeBSD__) || defined(__APPLE__)
    struct tm *tm_ptr = gmtime_r(&now, &tm_buf);
#else
    struct tm *tm_ptr = std::gmtime(&now);
    if (tm_ptr != nullptr) {
      tm_buf = *tm_ptr;
      tm_ptr = &tm_buf;
    }
#endif
    if (tm_ptr != nullptr) {
      std::strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", tm_ptr);
    }
  }

  if (file != nullptr && line > 0) {
    std::fprintf(f, "[%s] %s %s:%d: %s\n", ts, level, file, line, message);
  } else {
    std::fprintf(f, "[%s] %s %s\n", ts, level, message);
  }
  std::fflush(f);
  std::fclose(f);
}

static void vlogLevel(const char *level, const char *file, int line, const char *fmt, std::va_list args) {
  char buf[2048];
  std::vsnprintf(buf, sizeof(buf), fmt, args);
  buf[sizeof(buf) - 1] = '\0';
  appendLine(level, file, line, buf);
}

const char *AppFileLog::LogPath() {
  const char *p = bootTraceLogPath();
  if (p != nullptr && p[0] != '\0') {
    return p;
  }
  return g_ActiveLogPath;
}

void AppFileLog::InitSession() {
  g_ActiveLogPath = kTitleLogPath;
  bootTrace("======== PS4 Linux session (guest) ========");
  Info("======== PS4 Linux app session start PKG v%s APP %s ========", PS4_LINUX_PKG_VERSION,
       PS4_LINUX_PKG_APP_VER);
}

void AppFileLog::Info(const char *p_Format, ...) {
  std::va_list args;
  va_start(args, p_Format);
  vlogLevel("INFO", nullptr, 0, p_Format, args);
  va_end(args);
}

void AppFileLog::Warn(const char *p_File, int p_Line, const char *p_Format, ...) {
  std::va_list args;
  va_start(args, p_Format);
  vlogLevel("WARN", p_File, p_Line, p_Format, args);
  va_end(args);
}

void AppFileLog::Error(const char *p_File, int p_Line, const char *p_Format, ...) {
  std::va_list args;
  va_start(args, p_Format);
  vlogLevel("ERROR", p_File, p_Line, p_Format, args);
  va_end(args);
}

void AppFileLog::ErrorErrno(const char *p_File, int p_Line, const char *p_Context, int p_Errno) {
  const char *errMsg = std::strerror(p_Errno);
  if (errMsg == nullptr) {
    errMsg = "unknown";
  }
  Error(p_File, p_Line, "%s (errno=%d %s)", p_Context, p_Errno, errMsg);
}
