# Package metadata
TITLE         := PS4 Linux
PKG_LABEL     ?= $(shell cat PKG_VERSION 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(PKG_LABEL)),)
PKG_LABEL     := 0.7.0
endif
MASTER_VERSION ?= $(shell cat .pkg-master-ver 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(MASTER_VERSION)),)
MASTER_VERSION := 01.00
endif
APP_VER_VALUE ?= $(shell cat .pkg-app-ver 2>/dev/null | tr -d '[:space:]')
ifeq ($(strip $(APP_VER_VALUE)),)
APP_VER_VALUE := 00.70
endif
TITLE_ID      := CSTP00003
CONTENT_ID    := IV0000-CSTP00003_00-PS4LINUXL0700001
# Apollo / OpenOrbis samples: PAID + 0x88-byte authinfo — see tmp/docs/PS4-LINUX-INTERNAL-RUNBOOK.md §3.
PAID          := 0x3800000000000011
AUTHINFO      := 000000000000000000000000001C004000FF000000000080000000000000000000000000000000000000008000400040000000000000008000000000000000080040FFFF000000F000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

LIBS          := -lc -lkernel -lc++ -lSceVideoOut -lSceGnmDriver -lSceSysmodule -lSceFreeType -lScePad -lSceUserService -lSceSystemService -lSceLibcInternal
LIBS					+= -Llibs -lLog

INCLUDES      := -Iinclude -Iexternal
ERRORFLAGS    := -Wall -Wextra -Wpedantic -Werror
OTHERFLAGS    := -std=c17 -O3 -D_DEFAULT_SOURCE
OTHERCXXFLAGS := -std=c++17

TOOLCHAIN     := $(OO_PS4_TOOLCHAIN)
ODIR          := build

ASSETS        := $(shell find assets -type f -name '*.*')
SCEMODULES    := $(shell find sce_module -type f -name '*.*')
SCESYS        := $(shell find sce_sys -type f -name '*.*')

SDIR          := src
EXTRAFLAGS    := $(INCLUDES) $(ERRORFLAGS) $(OTHERFLAGS)
CFLAGS        := --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -c -isysroot $(TOOLCHAIN) -isystem $(TOOLCHAIN)/include $(EXTRAFLAGS)
CXXFLAGS      := $(CFLAGS) -isystem $(TOOLCHAIN)/include/c++/v1 $(OTHERCXXFLAGS)
LDFLAGS       := -m elf_x86_64 -pie --script $(TOOLCHAIN)/link.x --eh-frame-hdr -L$(TOOLCHAIN)/lib $(TOOLCHAIN)/lib/crt1.o

CFILES        := $(wildcard $(SDIR)/*.c)
CFILES        := $(filter-out $(SDIR)/ChainLauncher.c $(SDIR)/GuestPlainLoader.c,$(CFILES))
CPPFILES      := $(wildcard $(SDIR)/*.cpp)
CPPFILES      := $(filter-out $(SDIR)/PayloadsView.cpp,$(CPPFILES))

# Restore stages (hardware: ~88 KiB FSELF launches; ~1.6 MiB unified FSELF → CE-41839). See PS4LINUX_RESTORE_STAGE.
# 1 = BootTrace + ThinMain (black screen shell)
# 11 = main + module load, stop before Application (FSELF bisect on hardware)
# 12 = Application + Graphics + fonts (minimal on-screen menu, 8-entry FSELF target)
# 2 = LinuxLoaderView ship menu (lite config, no Settings — fits OneFamily FSELF)
# 3 = full menu (+ SettingsView, CreditView, nlohmann — may exceed 950 KiB)
# 3 = full unified menu (+ CreditView)
PS4LINUX_RESTORE_STAGE ?= 2
ifeq ($(PS4LINUX_THIN),1)
PS4LINUX_RESTORE_STAGE := 1
endif

RESTORE_STAGE11_CPP := main.cpp AppFileLog.cpp FailSafeGuest.cpp
RESTORE_STAGE12_CPP := main.cpp App.cpp Graphics.cpp Controller.cpp Resource.cpp LanguageMinimal.cpp Utility.cpp \
	AppFileLog.cpp FailSafeGuest.cpp SystemServiceRuntime.cpp
RESTORE_STAGE2_CPP := main.cpp App.cpp Graphics.cpp Controller.cpp Resource.cpp LanguageMinimal.cpp Utility.cpp \
	AppFileLog.cpp FailSafeGuest.cpp PlatformDetect.cpp LinuxInstallDetect.cpp LinuxBootConfigLite.cpp LinuxLoaderView.cpp SystemServiceRuntime.cpp
RESTORE_STAGE3_CPP := $(RESTORE_STAGE2_CPP) SettingsView.cpp Language.cpp LinuxBootConfig.cpp
RESTORE_STAGE3_EXTRA_CPP := CreditView.cpp

RESTORE_FULL_LIBS := -lc -lkernel -lc++ -lSceVideoOut -lSceGnmDriver -lSceSysmodule -lSceFreeType -lScePad -lSceKeyboard -lSceUserService -lSceSystemService -lSceLibcInternal -Llibs -lLog

# GoldHEN CSTP00003: match OneFamily (~899 KiB 8-entry FSELF). See FselfShipGate.validateGoldHenOneFamilyShipProfile.
PS4LINUX_EBOOT_MAX_BYTES ?= 950000

ifeq ($(PS4LINUX_RESTORE_STAGE),1)
CFILES        := $(SDIR)/BootTrace.c $(SDIR)/ThinMain.c
CPPFILES      :=
LIBS          := -lc -lkernel -lSceSysmodule -lSceSystemService -Llibs -lLog
PS4LINUX_EBOOT_MIN_BYTES := 65536
else ifeq ($(PS4LINUX_RESTORE_STAGE),11)
CFILES        := $(SDIR)/BootTrace.c $(SDIR)/FailSafe.c
CPPFILES      := $(addprefix $(SDIR)/,$(RESTORE_STAGE11_CPP))
LIBS          := $(RESTORE_FULL_LIBS)
CXXFLAGS      += -DPS4LINUX_STOP_BEFORE_APPLICATION
PS4LINUX_EBOOT_MIN_BYTES := 65536
else ifeq ($(PS4LINUX_RESTORE_STAGE),12)
CFILES        := $(SDIR)/BootTrace.c $(SDIR)/FailSafe.c
CPPFILES      := $(addprefix $(SDIR)/,$(RESTORE_STAGE12_CPP))
LIBS          := $(RESTORE_FULL_LIBS)
CXXFLAGS      += -DPS4LINUX_MINIMAL_MENU -Os
CFLAGS        += -Os
PS4LINUX_EBOOT_MIN_BYTES := 65536
else ifeq ($(PS4LINUX_RESTORE_STAGE),2)
CFILES        := $(SDIR)/BootTrace.c $(SDIR)/FailSafe.c
CPPFILES      := $(addprefix $(SDIR)/,$(RESTORE_STAGE2_CPP))
LIBS          := $(RESTORE_FULL_LIBS)
CXXFLAGS      += -DPS4LINUX_NO_SETTINGS -Os
CFLAGS        += -Os
# Bravia / HDMI CEC remote + system std pad (Home bit filtered — see Controller.cpp).
PS4LINUX_TV_REMOTE_INPUT ?= 1
ifeq ($(PS4LINUX_TV_REMOTE_INPUT),1)
CXXFLAGS      += -DPS4LINUX_TV_REMOTE_INPUT=1
else
CXXFLAGS      += -DPS4LINUX_TV_REMOTE_INPUT=0
endif
PS4LINUX_EBOOT_MIN_BYTES := 65536
else ifeq ($(PS4LINUX_RESTORE_STAGE),3)
CFILES        := $(filter-out $(SDIR)/ThinMain.c $(SDIR)/ChainLauncher.c $(SDIR)/GuestPlainLoader.c,$(CFILES))
CPPFILES      := $(addprefix $(SDIR)/,$(RESTORE_STAGE3_CPP) $(RESTORE_STAGE3_EXTRA_CPP))
PS4LINUX_EBOOT_MIN_BYTES := 524288
else
CFILES        := $(filter-out $(SDIR)/ThinMain.c,$(CFILES))
CPPFILES      := $(filter-out $(SDIR)/PayloadsView.cpp,$(CPPFILES))
PS4LINUX_EBOOT_MIN_BYTES := 524288
endif

MENU_OBJS     := $(patsubst $(SDIR)/%.c, $(ODIR)/%.o, $(CFILES)) $(patsubst $(SDIR)/%.cpp, $(ODIR)/%.o, $(CPPFILES))

REPO_ROOT     := $(abspath ../..)

UNAME_S := $(shell uname -s)
FSELF     := create-fself
ifeq ($(UNAME_S),Linux)
		CC        := clang
		CXX       := clang++
		PS4LINUX_LD ?= ld.lld
		CDIR      := linux
endif
ifeq ($(UNAME_S),Darwin)
		FSELF     := create-fself-macos
		CC        := $(if $(PS4LINUX_CC),$(PS4LINUX_CC),$(if $(CC),$(CC),/usr/local/opt/llvm/bin/clang))
		CXX       := $(if $(PS4LINUX_CXX),$(PS4LINUX_CXX),$(if $(CXX),$(CXX),/usr/local/opt/llvm/bin/clang++))
		PS4LINUX_LD ?= $(REPO_ROOT)/vendor/llvm-macos/bin/ld.lld
		CDIR      := macos
endif
PS4LINUX_LD     ?= ld.lld

PS4LINUX_FSELF := $(REPO_ROOT)/tools/ps4-linux-fself.sh

FSELF_TOOL := $(TOOLCHAIN)/bin/$(CDIR)/$(FSELF)
FSELF_ENV  :=
ifneq ($(strip $(PS4LINUX_FSELF_WRAPPER)),)
FSELF_TOOL := $(PS4LINUX_FSELF_WRAPPER)
FSELF_ENV  := OO_PS4_TOOLCHAIN=$(TOOLCHAIN)
endif

.PHONY: all pkg.gp4 sce_sys/param.sfo eboot.bin verify-layout clean
.DEFAULT := all

all: $(CONTENT_ID).pkg

$(CONTENT_ID).pkg: pkg.gp4 verify-layout
	$(TOOLCHAIN)/bin/$(CDIR)/PkgTool.Core pkg_build $< .

verify-layout: eboot.bin pkg.gp4
	@test $$(stat -f%z eboot.bin) -ge $(PS4LINUX_EBOOT_MIN_BYTES) || (echo "FAIL: eboot.bin too small — split-chain / CE-34878 regression (need unified eboot)" && exit 1)
	@test $$(stat -f%z eboot.bin) -le $(PS4LINUX_EBOOT_MAX_BYTES) || (echo "FAIL: eboot.bin exceeds GoldHEN OneFamily ceiling ($(PS4LINUX_EBOOT_MAX_BYTES) B) — shrink link or CE-41839-5" && exit 1)
	@test ! -f assets/boot/guest.oelf || (echo "FAIL: remove assets/boot/guest.oelf — menu must be in eboot.bin" && exit 1)
	@test ! -f guest.elf || (echo "FAIL: remove root guest.elf" && exit 1)
	@test ! -f assets/boot/guest.elf || (echo "FAIL: remove assets/boot/guest.elf — use unified eboot only" && exit 1)
	@grep -q 'targ_path="eboot.bin"' pkg.gp4 || (echo "FAIL: pkg.gp4 missing eboot.bin" && exit 1)
	@grep -q 'guest.oelf' pkg.gp4 && (echo "FAIL: pkg.gp4 must not ship guest.oelf" && exit 1) || true
	@echo "verify-layout OK (unified eboot=$$(stat -f%z eboot.bin))"

pkg.gp4: eboot.bin sce_sys/param.sfo $(SCESYS) $(SCEMODULES) $(ASSETS)
	$(TOOLCHAIN)/bin/$(CDIR)/create-gp4 -out $@ --content-id=$(CONTENT_ID) --files "$^"
	@python3 -c "import pathlib; p=pathlib.Path('$@'); t=p.read_text(); t=t.replace('<dir targ_name=\"images\" />', '<dir targ_name=\"images\" />\\n\t\t\t<dir targ_name=\"languages\" />') if 'languages' not in t.split('rootdir')[1][:800] else t; p.write_text(t)"

sce_sys/param.sfo: Makefile .pkg-app-ver .pkg-master-ver
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

eboot.bin: $(ODIR) $(MENU_OBJS)
	$(PS4LINUX_LD) $(MENU_OBJS) -o $(ODIR)/eboot.elf $(LDFLAGS) $(LIBS)
	@chmod +x $(PS4LINUX_FSELF)
	$(FSELF_ENV) $(PS4LINUX_FSELF) -in=$(ODIR)/eboot.elf -out=$(ODIR)/eboot.oelf --eboot "eboot.bin" --paid $(PAID) --authinfo=$(AUTHINFO)
	@if [ "$(PS4LINUX_RESTORE_STAGE)" = "1" ] || [ "$(PS4LINUX_RESTORE_STAGE)" = "11" ]; then touch .ps4-linux-thin-eboot; else rm -f .ps4-linux-thin-eboot; fi

$(ODIR)/%.o: $(SDIR)/%.c
	$(CC) $(CFLAGS) -o $@ $<

$(ODIR)/%.o: $(SDIR)/%.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

$(ODIR):
	@mkdir -p $@

clean:
	rm -rf *.pkg PS4-Linux-v*.pkg pkg.gp4 sce_sys/param.sfo eboot.bin assets/boot/guest.oelf assets/boot/guest.elf linux_menu.elf guest.elf $(ODIR)
