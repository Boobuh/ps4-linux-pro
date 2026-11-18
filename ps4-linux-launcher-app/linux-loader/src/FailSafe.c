#include "FailSafe.h"
#include "PkgLayout.h"

#include "BootTrace.h"
#include "libLog.h"
#include "notifi.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failSafeEnsureParentDir(const char *filePath) {
  if (filePath == NULL) {
    return -1;
  }
  char dir[512];
  (void)snprintf(dir, sizeof(dir), "%s", filePath);
  char *slash = strrchr(dir, '/');
  if (slash == NULL || slash == dir) {
    return 0;
  }
  *slash = '\0';
  for (char *p = dir + 1; *p != '\0'; p++) {
    if (*p != '/') {
      continue;
    }
    *p = '\0';
    if (mkdir(dir, 0755) != 0 && errno != EEXIST) {
      *p = '/';
      continue;
    }
    *p = '/';
  }
  if (mkdir(dir, 0755) != 0 && errno != EEXIST) {
    return -1;
  }
  return 0;
}

static const char *kMenuLoadOrder[] = {
    PS4LINUX_MENU_APP0_PATH,
    PS4LINUX_MENU_LEGACY_APP0_LINUX_MENU,
    PS4LINUX_MENU_LEGACY_APP0_GUEST,
    PS4LINUX_MENU_SYNC_PATH,
    PS4LINUX_MENU_CACHE_USER,
    NULL,
};

static off_t measureSeekEnd(int fd) {
  if (lseek(fd, 0, SEEK_SET) < 0) {
    return -1;
  }
  return lseek(fd, 0, SEEK_END);
}

int failSafeReadMagic4(int fd, unsigned char outMagic[4]) {
  if (outMagic == NULL) {
    return -1;
  }
  if (lseek(fd, 0, SEEK_SET) < 0) {
    return -1;
  }
  if (read(fd, outMagic, 4) != 4) {
    return -1;
  }
  return 0;
}

int failSafeIsFselfMagic(const unsigned char magic[4]) {
  return magic[0] == 0x4f && magic[1] == 0x15 && magic[2] == 0x3d && magic[3] == 0x1d;
}

int failSafeVerifyMenuBinary(const char *path, off_t minBytes, off_t *outSeekSize) {
  if (path == NULL) {
    return -1;
  }

  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    return -1;
  }

  unsigned char magic[4];
  if (failSafeReadMagic4(fd, magic) != 0 || !failSafeIsFselfMagic(magic)) {
    close(fd);
    return -1;
  }

  const off_t sz = measureSeekEnd(fd);
  close(fd);

  if (outSeekSize != NULL) {
    *outSeekSize = sz;
  }
  if (sz < minBytes) {
    return -1;
  }
  return 0;
}

int failSafeMaterializeFile(const char *srcPath, const char *dstPath, off_t minBytes) {
  if (srcPath == NULL || dstPath == NULL) {
    return -1;
  }

  int inFd = open(srcPath, O_RDONLY);
  if (inFd < 0) {
    return -1;
  }

  const off_t total = measureSeekEnd(inFd);
  if (total < minBytes) {
    close(inFd);
    return -1;
  }
  if (lseek(inFd, 0, SEEK_SET) < 0) {
    close(inFd);
    return -1;
  }

  (void)failSafeEnsureParentDir(dstPath);

  int outFd = open(dstPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (outFd < 0) {
    char line[160];
    (void)snprintf(line, sizeof(line), "eboot: materialize open dst errno=%d path=%s", errno, dstPath);
    bootTrace(line);
    close(inFd);
    return -1;
  }

  char buf[65536];
  off_t done = 0;
  while (done < total) {
    const size_t want =
        (size_t)((total - done) > (off_t)sizeof(buf) ? sizeof(buf) : (size_t)(total - done));
    const ssize_t n = read(inFd, buf, want);
    if (n <= 0) {
      break;
    }
    if (write(outFd, buf, (size_t)n) != n) {
      break;
    }
    done += n;
  }

  close(inFd);
  close(outFd);

  if (done != total) {
    return -1;
  }

  (void)truncate(dstPath, (off_t)total);
  return failSafeVerifyMenuBinary(dstPath, minBytes, NULL);
}

void failSafeNotify(const char *fmt, ...) {
  if (fmt == NULL) {
    return;
  }
  char msg[768];
  va_list args;
  va_start(args, fmt);
  (void)vsnprintf(msg, sizeof(msg), fmt, args);
  va_end(args);
  msg[sizeof(msg) - 1] = '\0';
  bootTrace(msg);
  logKernel(LL_Error, "%s", msg);
  notifi(NULL, "%s", msg);
}

void failSafeHoldAndExit(int exitCode, const char *reason) {
  if (reason != NULL) {
    failSafeNotify("PS4 Linux: %s (see FTP log)", reason);
  }
  bootTrace("eboot: fail-safe hold 15s before exit");
  for (int i = 0; i < 30; i++) {
    usleep(500000);
  }
  _exit(exitCode);
}

int failSafeIsKexecBinPayload(const char *path) {
  if (path == NULL) {
    return 0;
  }
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    return 0;
  }
  unsigned char magic[4];
  if (failSafeReadMagic4(fd, magic) != 0) {
    close(fd);
    return 0;
  }
  if (failSafeIsFselfMagic(magic)) {
    close(fd);
    return 0;
  }
  if (magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F') {
    close(fd);
    return 0;
  }
  const off_t sz = measureSeekEnd(fd);
  close(fd);
  if (sz < 8192 || sz > 2 * 1024 * 1024) {
    return 0;
  }
  return 1;
}

int failSafeResolveMenuLoadPath(char *outPath, size_t outPathLen) {
  if (outPath == NULL || outPathLen < 2) {
    return -1;
  }

  off_t bytes = 0;
  for (int i = 0; kMenuLoadOrder[i] != NULL; i++) {
    if (failSafeVerifyMenuBinary(kMenuLoadOrder[i], FAILSAFE_MENU_MIN_BYTES, &bytes) != 0) {
      continue;
    }
    (void)snprintf(outPath, outPathLen, "%s", kMenuLoadOrder[i]);
    char line[256];
    (void)snprintf(line, sizeof(line), "eboot: menu autodetect %s size=%lld", kMenuLoadOrder[i], (long long)bytes);
    bootTrace(line);
    return 0;
  }

  return -1;
}
