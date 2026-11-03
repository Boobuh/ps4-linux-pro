# Package metadata
TITLE         := PS4 Linux
# Semantic pre-release label (in-app only); param.sfo VERSION (master) bumps with each build via ps4-linux-launcher-build.swift.
PKG_LABEL     ?= $(shell cat PKG_VERSION 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(PKG_LABEL)),)
PKG_LABEL     := 0.7.0
endif
# param.sfo VERSION (master) and APP_VER — both must change for Package Installer updates.
MASTER_VERSION ?= $(shell cat .pkg-master-ver 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(MASTER_VERSION)),)
MASTER_VERSION := 01.00
endif
# APP_VER (application version) — Sony XX.YY, max 7 chars; from .pkg-app-ver or build script
APP_VER_VALUE ?= $(shell cat .pkg-app-ver 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(APP_VER_VALUE)),)
APP_VER_VALUE := 00.70
endif
TITLE_ID      := CSTP00002
CONTENT_ID    := IV0000-CSTP00002_00-PS4LINUXL0700000
AUTHINFO      := 000000000000000000000000001C004000FF000000000080000000000000000000000000000000000000008000400040000000000000008000000000000000080040FFFF000000F000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

# Libraries linked into the ELF
LIBS          := -lc -lkernel -lc++ -lSceVideoOut -lSceGnmDriver -lSceSysmodule -lSceFreeType -lScePad -lSceUserService -lSceSystemService -lSceLibcInternal
LIBS					+= -Llibs -lLog

# Directorys to include
INCLUDES      := -Iinclude -Iexternal

# Additional compile flags
#   ERRORFLAGS and OTHERFLAGS will be included in C and C++ flags
#   OTHERCXXFLAGS will only be included in C++ flags
ERRORFLAGS    := -Wall -Wextra -Wpedantic -Werror
OTHERFLAGS    := -std=c17 -O3 -D_DEFAULT_SOURCE
OTHERCXXFLAGS := -std=c++17

# PKG Asset directories
ASSETS        := $(shell find assets -type f -name '*.*')
SCEMODULES    := $(shell find sce_module -type f -name '*.*')
SCESYS        := $(shell find sce_sys -type f -name '*.*')

# -----------------------------------------------------------------------------
# Do not edit below this line unless you know what you are doing
# -----------------------------------------------------------------------------

TOOLCHAIN     := $(OO_PS4_TOOLCHAIN)
ODIR          := build
SDIR          := src
EXTRAFLAGS    := $(INCLUDES) $(ERRORFLAGS) $(OTHERFLAGS)
CFLAGS        := --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -c -isysroot $(TOOLCHAIN) -isystem $(TOOLCHAIN)/include $(EXTRAFLAGS)
CXXFLAGS      := $(CFLAGS) -isystem $(TOOLCHAIN)/include/c++/v1 $(OTHERCXXFLAGS)
LDFLAGS       := -m elf_x86_64 -pie --script $(TOOLCHAIN)/link.x --eh-frame-hdr -L$(TOOLCHAIN)/lib $(LIBS) $(TOOLCHAIN)/lib/crt1.o

CFILES        := $(wildcard $(SDIR)/*.c)
CFILES        := $(filter-out $(SDIR)/ChainLauncher.c,$(CFILES))
CPPFILES      := $(wildcard $(SDIR)/*.cpp)
CPPFILES      := $(filter-out $(SDIR)/PayloadsView.cpp,$(CPPFILES))
OBJS          := $(patsubst $(SDIR)/%.c, $(ODIR)/%.o, $(CFILES)) $(patsubst $(SDIR)/%.cpp, $(ODIR)/%.o, $(CPPFILES))
OBJS          := $(filter-out $(ODIR)/eboot.o,$(OBJS))

UNAME_S := $(shell uname -s)
FSELF     := create-fself
ifeq ($(UNAME_S),Linux)
		CC        := clang
		CXX       := clang++
		LD        := ld.lld
		CDIR      := linux
endif
ifeq ($(UNAME_S),Darwin)
		FSELF     := create-fself-macos
		CC        := $(if $(CC),$(CC),/usr/local/opt/llvm/bin/clang)
		CXX       := $(if $(CXX),$(CXX),/usr/local/opt/llvm/bin/clang++)
		LD        := $(if $(LD),$(LD),/usr/local/opt/llvm/bin/ld.lld)
		CDIR      := macos
endif

.PHONY: all pkg.gp4 sce_sys/param.sfo eboot.bin guest.elf clean
.DEFAULT := all

all: $(CONTENT_ID).pkg

$(CONTENT_ID).pkg: pkg.gp4
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core pkg_build $< .

pkg.gp4: eboot.bin guest.elf sce_sys/param.sfo $(SCESYS) $(SCEMODULES) $(ASSETS)
	$(TOOLCHAIN)/bin/$(CDIR)/create-gp4 -out $@ --content-id=$(CONTENT_ID) --files "$^"
	@python3 -c "import pathlib; p=pathlib.Path('$@'); t=p.read_text(); t=t.replace('<dir targ_name=\"images\" />', '<dir targ_name=\"images\" />\\n\t\t\t<dir targ_name=\"languages\" />') if 'languages' not in t.split('rootdir')[1][:800] else t; p.write_text(t)"

sce_sys/param.sfo: Makefile .pkg-app-ver .pkg-master-ver
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_new $@
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ APP_TYPE --type Integer --maxsize 4 --value 1
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ APP_VER --type Utf8 --maxsize 8 --value '$(APP_VER_VALUE)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ ATTRIBUTE --type Integer --maxsize 4 --value 0
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ CATEGORY --type Utf8 --maxsize 4 --value 'gd'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ CONTENT_ID --type Utf8 --maxsize 48 --value '$(CONTENT_ID)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ DOWNLOAD_DATA_SIZE --type Integer --maxsize 4 --value 0
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ SYSTEM_VER --type Integer --maxsize 4 --value 0
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ TITLE --type Utf8 --maxsize 128 --value '$(TITLE)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ TITLE_ID --type Utf8 --maxsize 12 --value '$(TITLE_ID)'
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core sfo_setentry $@ VERSION --type Utf8 --maxsize 8 --value '$(MASTER_VERSION)'

eboot.bin: guest.elf $(ODIR)/BootTrace.o
	$(CC) --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -c -isysroot $(TOOLCHAIN) -isystem $(TOOLCHAIN)/include $(INCLUDES) -std=c99 -O3 -D_DEFAULT_SOURCE $(ERRORFLAGS) -o $(ODIR)/eboot.o $(SDIR)/ChainLauncher.c
	$(LD) $(ODIR)/eboot.o $(ODIR)/BootTrace.o -o $(ODIR)/eboot.elf -m elf_x86_64 -pie --script $(TOOLCHAIN)/link.x --eh-frame-hdr -L$(TOOLCHAIN)/lib -lc -lkernel -lSceSysmodule -lSceSystemService -Llibs -lLog $(TOOLCHAIN)/lib/crt1.o
	$(TOOLCHAIN)/bin/$(CDIR)/$(FSELF) -in=$(ODIR)/eboot.elf -out=$(ODIR)/eboot.oelf --eboot "eboot.bin" --authinfo=$(AUTHINFO)

guest.elf: $(ODIR) $(OBJS)
	$(LD) $(OBJS) -o $(ODIR)/guest.elf $(LDFLAGS)
	$(TOOLCHAIN)/bin/$(CDIR)/$(FSELF) -in=$(ODIR)/guest.elf -out=$(ODIR)/guest.oelf --eboot "guest.elf" --authinfo=$(AUTHINFO)

$(ODIR)/%.o: $(SDIR)/%.c
	$(CC) $(CFLAGS) -o $@ $<

$(ODIR)/%.o: $(SDIR)/%.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

$(ODIR):
	@mkdir -p $@

clean:
	rm -rf *.pkg PS4-Linux-v*.pkg pkg.gp4 sce_sys/param.sfo eboot.bin guest.elf $(ODIR)
