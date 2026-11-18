#include "GuestPlainLoader.h"

#include "BootTrace.h"
#include "PkgLayout.h"

#include <dlfcn.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static off_t fileSeekSize(int fd) {
  if (lseek(fd, 0, SEEK_SET) < 0) {
    return -1;
  }
  return lseek(fd, 0, SEEK_END);
}

static int readAt(int fd, off_t off, void *buf, size_t len) {
  if (lseek(fd, off, SEEK_SET) < 0) {
    return -1;
  }
  size_t done = 0;
  while (done < len) {
    const ssize_t n = read(fd, (char *)buf + done, len - done);
    if (n <= 0) {
      return -1;
    }
    done += (size_t)n;
  }
  return 0;
}

int guestPlainLoaderRun(const char *path) {
  if (path == NULL) {
    return -1;
  }

  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    char line[160];
    (void)snprintf(line, sizeof(line), "loader: open %s errno=%d", path, errno);
    bootTrace(line);
    return -1;
  }

  const off_t fileSize = fileSeekSize(fd);
  if (fileSize < (off_t)PS4LINUX_MENU_MIN_BYTES) {
    bootTrace("loader: menu file too small");
    close(fd);
    return -1;
  }

  Elf64_Ehdr ehdr;
  if (readAt(fd, 0, &ehdr, sizeof(ehdr)) != 0) {
    bootTrace("loader: ehdr read failed");
    close(fd);
    return -1;
  }
  if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0 || ehdr.e_ident[EI_CLASS] != ELFCLASS64) {
    bootTrace("loader: not ELF64");
    close(fd);
    return -1;
  }
  if (ehdr.e_type != ET_DYN && ehdr.e_type != ET_EXEC) {
    bootTrace("loader: unsupported ELF type");
    close(fd);
    return -1;
  }

  uint64_t minVaddr = UINT64_MAX;
  uint64_t maxVaddr = 0;
  for (uint16_t i = 0; i < ehdr.e_phnum; i++) {
    Elf64_Phdr phdr;
    const off_t phOff = (off_t)ehdr.e_phoff + (off_t)i * (off_t)sizeof(Elf64_Phdr);
    if (readAt(fd, phOff, &phdr, sizeof(phdr)) != 0) {
      continue;
    }
    if (phdr.p_type != PT_LOAD) {
      continue;
    }
    if (phdr.p_vaddr < minVaddr) {
      minVaddr = phdr.p_vaddr;
    }
    const uint64_t end = phdr.p_vaddr + phdr.p_memsz;
    if (end > maxVaddr) {
      maxVaddr = end;
    }
  }

  if (maxVaddr <= minVaddr) {
    bootTrace("loader: no PT_LOAD");
    close(fd);
    return -1;
  }

  const size_t mapSize = (size_t)(maxVaddr - minVaddr);
  void *base = mmap(NULL, mapSize, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (base == MAP_FAILED) {
    bootTrace("loader: mmap failed");
    close(fd);
    return -1;
  }
  memset(base, 0, mapSize);

  for (uint16_t i = 0; i < ehdr.e_phnum; i++) {
    Elf64_Phdr phdr;
    const off_t phOff = (off_t)ehdr.e_phoff + (off_t)i * (off_t)sizeof(Elf64_Phdr);
    if (readAt(fd, phOff, &phdr, sizeof(phdr)) != 0) {
      continue;
    }
    if (phdr.p_type != PT_LOAD || phdr.p_filesz == 0) {
      continue;
    }
    void *dest = (char *)base + (phdr.p_vaddr - minVaddr);
    if (readAt(fd, (off_t)phdr.p_offset, dest, (size_t)phdr.p_filesz) != 0) {
      bootTrace("loader: segment read failed");
      munmap(base, mapSize);
      close(fd);
      return -1;
    }
  }

  const uint64_t loadBase = (uint64_t)(uintptr_t)base - minVaddr;

  Elf64_Sym *dynsym = NULL;
  const char *dynstr = NULL;
  Elf64_Rela *rela = NULL;
  size_t relaCount = 0;
  uint64_t initAddr = 0;

  for (uint16_t i = 0; i < ehdr.e_phnum; i++) {
    Elf64_Phdr phdr;
    const off_t phOff = (off_t)ehdr.e_phoff + (off_t)i * (off_t)sizeof(Elf64_Phdr);
    if (readAt(fd, phOff, &phdr, sizeof(phdr)) != 0) {
      continue;
    }
    if (phdr.p_type != PT_DYNAMIC) {
      continue;
    }
    Elf64_Dyn *dynMapped = (Elf64_Dyn *)((char *)base + (phdr.p_vaddr - minVaddr));
    for (size_t d = 0; dynMapped[d].d_tag != DT_NULL; d++) {
      switch (dynMapped[d].d_tag) {
      case DT_SYMTAB:
        dynsym = (Elf64_Sym *)(uintptr_t)(loadBase + dynMapped[d].d_un.d_ptr);
        break;
      case DT_STRTAB:
        dynstr = (const char *)(uintptr_t)(loadBase + dynMapped[d].d_un.d_ptr);
        break;
      case DT_RELA:
        rela = (Elf64_Rela *)(uintptr_t)(loadBase + dynMapped[d].d_un.d_ptr);
        break;
      case DT_RELASZ:
        relaCount = (size_t)(dynMapped[d].d_un.d_val / sizeof(Elf64_Rela));
        break;
      case DT_INIT:
        initAddr = loadBase + dynMapped[d].d_un.d_ptr;
        break;
      default:
        break;
      }
    }
    break;
  }

  size_t relativeCount = 0;
  size_t jumpSlotCount = 0;
  if (rela != NULL && relaCount > 0) {
    for (size_t r = 0; r < relaCount; r++) {
      const uint32_t rType = ELF64_R_TYPE(rela[r].r_info);
      if (rType == R_X86_64_RELATIVE) {
        uint64_t *loc = (uint64_t *)(uintptr_t)(loadBase + rela[r].r_offset);
        *loc = loadBase + rela[r].r_addend;
        relativeCount++;
      } else if (rType == R_X86_64_JUMP_SLOT) {
        if (dynsym == NULL || dynstr == NULL) {
          bootTrace("loader: JUMP_SLOT without dynsym/dynstr");
          munmap(base, mapSize);
          close(fd);
          return -1;
        }
        const uint32_t symIdx = ELF64_R_SYM(rela[r].r_info);
        const char *symName = dynstr + dynsym[symIdx].st_name;
        void *addr = dlsym(RTLD_DEFAULT, symName);
        if (addr == NULL) {
          char miss[160];
          (void)snprintf(miss, sizeof(miss), "loader: dlsym failed sym=%s", symName);
          bootTrace(miss);
          munmap(base, mapSize);
          close(fd);
          return -1;
        }
        uint64_t *loc = (uint64_t *)(uintptr_t)(loadBase + rela[r].r_offset);
        *loc = (uint64_t)(uintptr_t)addr;
        jumpSlotCount++;
      }
    }
  }

  char relocLine[160];
  (void)snprintf(relocLine, sizeof(relocLine), "loader: relocs RELATIVE=%zu JUMP_SLOT=%zu", relativeCount,
                 jumpSlotCount);
  bootTrace(relocLine);

  close(fd);

  if (initAddr != 0) {
    bootTrace("loader: DT_INIT");
    void (*initFn)(void) = (void (*)(void))(uintptr_t)initAddr;
    initFn();
  }

  char line[192];
  (void)snprintf(line, sizeof(line), "loader: running %s entry=0x%llx map=%zu", path, (unsigned long long)ehdr.e_entry,
                 mapSize);
  bootTrace(line);

  int (*entry)(void) = (int (*)(void))(uintptr_t)(loadBase + ehdr.e_entry);
  const int rc = entry();
  char retLine[96];
  (void)snprintf(retLine, sizeof(retLine), "loader: guest entry returned %d", rc);
  bootTrace(retLine);
  return rc;
}
