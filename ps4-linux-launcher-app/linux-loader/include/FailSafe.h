#pragma once

#include "PkgLayout.h"

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FAILSAFE_MENU_MIN_BYTES PS4LINUX_MENU_MIN_BYTES

/// FSELF magic 0x4F153D1D (first 4 bytes).
int failSafeReadMagic4(int fd, unsigned char outMagic[4]);

int failSafeIsFselfMagic(const unsigned char magic[4]);

/// True if path readable, FSELF magic OK, seek-autodetected size >= minBytes.
int failSafeVerifyMenuBinary(const char *path, off_t minBytes, off_t *outSeekSize);

/// Copy src → dst using seek size; verify dst the same way.
int failSafeMaterializeFile(const char *srcPath, const char *dstPath, off_t minBytes);

/// First load-order path that passes failSafeVerifyMenuBinary (seek size). outPath filled. Returns 0 on success.
int failSafeResolveMenuLoadPath(char *outPath, size_t outPathLen);

/// Log + PS4 notification (never crashes on format).
void failSafeNotify(const char *fmt, ...);

/// Log, notify, pause so the user can read, then exit (avoids instant silent home).
void failSafeHoldAndExit(int exitCode, const char *reason);

/// GoldHEN BinLoader expects raw .bin — reject FSELF/ELF and absurd sizes.
int failSafeIsKexecBinPayload(const char *path);

#ifdef __cplusplus
}
void failSafeGuestStop(const char *reason);
#endif
