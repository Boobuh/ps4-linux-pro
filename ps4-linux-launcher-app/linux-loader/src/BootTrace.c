#include "BootTrace.h"

#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static const char *kDefaultPath = "/user/app/CSTP00002/ps4-linux-app.log";
static const char *g_ActivePath = NULL;

static const char *logPaths[] = {
    "/user/app/CSTP00002/ps4-linux-app.log",
    "/user/.ps4-linux-app.log",
    "/user/data/ps4-linux-app.log",
    "/data/pkg/ps4-linux-app.log",
    "/data/linux/boot/ps4-linux-app.log",
    NULL,
};

void bootTrace(const char *message) {
  if (message == NULL) {
    return;
  }

  const char *tryPaths[8];
  int n = 0;
  if (g_ActivePath != NULL) {
    tryPaths[n++] = g_ActivePath;
  }
  for (int i = 0; logPaths[i] != NULL && n < 7; i++) {
    if (g_ActivePath != NULL && strcmp(logPaths[i], g_ActivePath) == 0) {
      continue;
    }
    tryPaths[n++] = logPaths[i];
  }
  tryPaths[n] = NULL;

  for (int i = 0; tryPaths[i] != NULL; i++) {
    int fd = open(tryPaths[i], O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) {
      continue;
    }
    g_ActivePath = tryPaths[i];
    (void)write(fd, message, strlen(message));
    (void)write(fd, "\n", 1);
    close(fd);
    return;
  }
}

const char *bootTraceLogPath(void) {
  if (g_ActivePath != NULL) {
    return g_ActivePath;
  }
  return kDefaultPath;
}
