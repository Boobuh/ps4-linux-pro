#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Map and run PIE/plain menu ELF from path (seek-sized read; no LoadExec). Returns 0 only if entry returns.
int guestPlainLoaderRun(const char *path);

#ifdef __cplusplus
}
#endif
