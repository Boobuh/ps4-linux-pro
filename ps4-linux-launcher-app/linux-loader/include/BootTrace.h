#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Append one line to all boot log paths (FTP: /data/linux/boot/ps4-linux-app.log).
void bootTrace(const char *message);

/// Same as bootTrace with a step: prefix and PKG version tag (blue-screen diagnosis).
void bootTraceStep(const char *step);

/// Primary log path for UI.
const char *bootTraceLogPath(void);

#ifdef __cplusplus
}
#endif
