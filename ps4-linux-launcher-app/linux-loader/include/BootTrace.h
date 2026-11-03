#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Append one line to the first writable boot log path (FTP-visible on GoldHEN).
void bootTrace(const char *message);

/// Path that last succeeded, or default for UI.
const char *bootTraceLogPath(void);

#ifdef __cplusplus
}
#endif
