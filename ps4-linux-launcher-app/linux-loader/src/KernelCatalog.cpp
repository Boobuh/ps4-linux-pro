#include "KernelCatalog.h"

#include <cstring>

static const KernelCatalogEntry kCatalog[] = {
    {
        "feernt-5.4.247-neocine",
        "feeRnt 5.4.247 neocine (Baikal Pro)",
        "https://github.com/feeRnt/ps4-linux-12xx/releases/download/v5.4.247__neocine-1.1/bzImage_GCC-11",
        "/data/linux/boot/bzImage",
        9872896,
        8000000,
        12000000,
    },
    {
        "fluffy-5.4.170-ps4",
        "Fluffy 5.4.170-ps4 (legacy Pro)",
        "https://github.com/iscsi-osx/ps4linux/releases/download/5.4.170-ps4/bzImage",
        "/data/linux/boot/bzImage",
        0,
        7500000,
        15000000,
    },
};

namespace KernelCatalog {

int Count() { return static_cast<int>(sizeof(kCatalog) / sizeof(kCatalog[0])); }

const KernelCatalogEntry &Entry(int index) {
  if (index < 0 || index >= Count()) {
    return kCatalog[0];
  }
  return kCatalog[index];
}

const KernelCatalogEntry *FindById(const char *id) {
  if (id == nullptr || id[0] == '\0') {
    return nullptr;
  }
  for (const auto &e : kCatalog) {
    if (std::strcmp(e.id, id) == 0) {
      return &e;
    }
  }
  return nullptr;
}

const char *DefaultKernelId() { return kCatalog[0].id; }

} // namespace KernelCatalog