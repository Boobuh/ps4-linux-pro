#ifndef KERNEL_CATALOG_H
#define KERNEL_CATALOG_H

#include <cstdint>

struct KernelCatalogEntry {
  const char *id;
  const char *title;
  const char *url;
  const char *destPath;
  int64_t expectedBytes;
  int64_t minBytes;
  int64_t maxBytes;
};

namespace KernelCatalog {
int Count();
const KernelCatalogEntry &Entry(int index);
const KernelCatalogEntry *FindById(const char *id);
const char *DefaultKernelId();
} // namespace KernelCatalog

#endif