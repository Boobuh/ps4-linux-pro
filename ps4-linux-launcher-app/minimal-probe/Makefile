TITLE         := PS4 Linux Minimal Probe
TITLE_ID      := CSTP00004
CONTENT_ID    := IV0000-CSTP00004_00-PS4LINUXM0000001
APP_VER_VALUE := 01.00
MASTER_VERSION := 01.00
PAID          := 0x3800000000000011
AUTHINFO      := 000000000000000000000000001C004000FF000000000080000000000000000000000000000000000000008000400040000000000000008000000000000000080040FFFF000000F000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

TOOLCHAIN     := $(OO_PS4_TOOLCHAIN)
REPO_ROOT     := $(abspath ../..)
PS4LINUX_FSELF := $(REPO_ROOT)/tools/ps4-linux-fself.sh
ODIR          := build

UNAME_S       := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  CC          := $(if $(CC),$(CC),/usr/local/opt/llvm/bin/clang)
  LD          := $(if $(LD),$(LD),/usr/local/opt/llvm/bin/ld.lld)
  CDIR        := macos
endif
ifeq ($(UNAME_S),Linux)
  CC          := clang
  LD          := ld.lld
  CDIR        := linux
endif

CFLAGS        := --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -c -isysroot $(TOOLCHAIN) -isystem $(TOOLCHAIN)/include -Wall -Wextra -std=c17 -O2
LDFLAGS       := -m elf_x86_64 -pie --script $(TOOLCHAIN)/link.x --eh-frame-hdr -L$(TOOLCHAIN)/lib -lc -lkernel $(TOOLCHAIN)/lib/crt1.o

ASSETS        := $(wildcard assets/*)
SCEMODULES    := $(wildcard sce_module/*.prx)
SCESYS        := $(wildcard sce_sys/**/*)

.PHONY: all clean pkg
all: PS4-Linux-MINIMAL-CSTP00004.pkg

PS4-Linux-MINIMAL-CSTP00004.pkg: pkg.gp4
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core pkg_build pkg.gp4 .

pkg.gp4: eboot.bin sce_sys/param.sfo $(SCESYS) $(SCEMODULES) $(ASSETS)
	$(TOOLCHAIN)/bin/$(CDIR)/create-gp4 -out $@ --content-id=$(CONTENT_ID) --files "$^"

sce_sys/param.sfo: Makefile
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_new $@
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ APP_TYPE --type Integer --maxsize 4 --value 1
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ APP_VER --type Utf8 --maxsize 8 --value '$(APP_VER_VALUE)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ ATTRIBUTE --type Integer --maxsize 4 --value 32
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ CATEGORY --type Utf8 --maxsize 4 --value 'gde'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ CONTENT_ID --type Utf8 --maxsize 48 --value '$(CONTENT_ID)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ DOWNLOAD_DATA_SIZE --type Integer --maxsize 4 --value 0
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ SYSTEM_VER --type Integer --maxsize 4 --value 0
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ TITLE --type Utf8 --maxsize 128 --value '$(TITLE)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ TITLE_ID --type Utf8 --maxsize 12 --value '$(TITLE_ID)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ VERSION --type Utf8 --maxsize 8 --value '$(MASTER_VERSION)'

eboot.bin: $(ODIR)/main.o
	$(LD) $(ODIR)/main.o -o $(ODIR)/eboot.elf $(LDFLAGS)
	$(PS4LINUX_FSELF) -in=$(ODIR)/eboot.elf -out=$(ODIR)/eboot.oelf --eboot "eboot.bin" --paid $(PAID) --authinfo=$(AUTHINFO)

$(ODIR)/main.o: src/main.c
	@mkdir -p $(ODIR)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -rf build eboot.bin pkg.gp4 sce_sys/param.sfo PS4-Linux-MINIMAL-CSTP00004.pkg
