#include "BootTrace.h"

#include "BuildVersion.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "libLog.h"

static const char *kStepLogPath = "/data/linux/boot/ps4-linux-last-run.txt";

static const char *logPaths[] = {
    "/data/linux/boot/ps4-linux-app.log",
    "/data/linux/boot/ps4-linux-last-run.txt",
    "/user/app/CSTP00003/ps4-linux-app.log",
    "/user/data/ps4-linux-app.log",
    "/user/.ps4-linux-app.log",
    "/data/pkg/ps4-linux-app.log",
    NULL,
};

static void ensureLogParentDir(const char *filePath) {
  if (filePath == NULL) {
    return;
  }
  char dir[512];
  (void)snprintf(dir, sizeof(dir), "%s", filePath);
  char *slash = strrchr(dir, '/');
  if (slash == NULL || slash == dir) {
    return;
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
  (void)mkdir(dir, 0755);
}

static void appendLineToPath(const char *path, const char *line) {
  if (path == NULL || line == NULL) {
    return;
  }
  ensureLogParentDir(path);
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
  if (fd < 0) {
    logKernel(LL_Warn, "bootTrace open fail path=%s errno=%d line=%s", path, errno, line);
    return;
  }
  (void)write(fd, line, strlen(line));
  (void)write(fd, "\n", 1);
  (void)fsync(fd);
  close(fd);
}

__attribute__((constructor(1))) static void bootTraceEarliest(void) {
  const char *line = "EARLY constructor (priority 1)\n";
  (void)write(1, line, strlen(line));
  appendLineToPath("/user/data/ps4-linux-early.txt", "EARLY constructor (priority 1)");
  appendLineToPath("/data/pkg/ps4-linux-early.txt", "EARLY constructor (priority 1)");
}

__attribute__((constructor(100))) static void bootTraceRunStart(void) {
  ensureLogParentDir("/data/linux/boot/ps4-linux-app.log");
  ensureLogParentDir(kStepLogPath);

  char header[256];
  (void)snprintf(header, sizeof(header), "===== RUN START pkg v%s build %s APP %s =====", PS4_LINUX_PKG_VERSION,
                 PS4_LINUX_PKG_BUILD, PS4_LINUX_PKG_APP_VER);
  logKernel(LL_Info, "%s", header);

  int fd = open(kStepLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd >= 0) {
    (void)write(fd, header, strlen(header));
    (void)write(fd, "\n", 1);
    (void)fsync(fd);
    close(fd);
  }
  appendLineToPath("/data/linux/boot/ps4-linux-app.log", header);
}

__attribute__((constructor(101))) static void bootTraceProcessStart(void) {
  bootTrace("app: process start (constructor, before main)");
}

void bootTraceStep(const char *step) {
  if (step == NULL) {
    return;
  }
  char line[384];
  (void)snprintf(line, sizeof(line), "step: %s [v%s]", step, PS4_LINUX_PKG_VERSION);
  bootTrace(line);
}

void bootTrace(const char *message) {
  if (message == NULL) {
    return;
  }

  logKernel(LL_Info, "%s", message);

  for (int i = 0; logPaths[i] != NULL; i++) {
    appendLineToPath(logPaths[i], message);
  }
}

const char *bootTraceLogPath(void) {
  return "/data/linux/boot/ps4-linux-app.log";
}
