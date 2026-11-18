#ifndef KERNEL_DOWNLOAD_H
#define KERNEL_DOWNLOAD_H

#include <cstdint>
#include <string>

#include "KernelCatalog.h"

struct KernelDownloadResult {
  bool ok = false;
  std::string error;
  int64_t bytesWritten = 0;
};

namespace KernelDownload {
KernelDownloadResult DownloadEntry(const KernelCatalogEntry &entry);
} // namespace KernelDownload

#endif