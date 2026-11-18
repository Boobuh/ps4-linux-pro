#include <fcntl.h>
#include <string.h>
#include <unistd.h>

__attribute__((constructor(1))) static void minimalProbeEarlyLog(void) {
  const char *line = "MINIMAL CSTP00004 constructor\n";
  const char *paths[] = {
      "/data/pkg/ps4-linux-minimal.log",
      "/user/data/ps4-linux-minimal.log",
      NULL,
  };
  for (int i = 0; paths[i] != NULL; i++) {
    int fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
      (void)write(fd, line, strlen(line));
      close(fd);
    }
  }
}

int main(void) {
  const char *line = "MINIMAL CSTP00004 main\n";
  int fd = open("/data/pkg/ps4-linux-minimal.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
  if (fd >= 0) {
    (void)write(fd, line, strlen(line));
    close(fd);
  }
  for (;;) {
    sleep(1);
  }
}
