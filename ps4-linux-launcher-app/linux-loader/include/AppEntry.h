#ifndef PS4_LINUX_APP_ENTRY_H
#define PS4_LINUX_APP_ENTRY_H

#ifdef __cplusplus
extern "C" {
#endif

// Full UI entry (main.cpp). Unified eboot — kernel loader, no LoadExec guest.
int ps4_linux_app_main(void);

#ifdef __cplusplus
}
#endif

#endif
