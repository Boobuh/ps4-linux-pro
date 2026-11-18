#ifndef LINUX_BOOT_STACK_CHECK_H
#define LINUX_BOOT_STACK_CHECK_H

#include <cstdint>
#include <string>

struct BootStackStatus {
  static constexpr const char *kBzImagePath = "/data/linux/boot/bzImage";
  static constexpr const char *kInitramfsPath = "/data/linux/boot/initramfs.cpio.gz";
  static constexpr const char *kKernelIdPath = "/data/linux/boot/ps4-kernel-id.txt";

  bool kernelPresent = false;
  bool kernelSizeOk = false;
  bool initramfsPresent = false;
  bool initramfsSizeOk = false;
  int64_t kernelBytes = -1;
  int64_t initramfsBytes = -1;
  std::string kernelId;

  bool ReadyForLaunch() const {
    return kernelPresent && kernelSizeOk && initramfsPresent && initramfsSizeOk;
  }

  std::string StatusLine() const;
  std::string LaunchBlockReason() const;
};

BootStackStatus InspectBootStack();

#endif