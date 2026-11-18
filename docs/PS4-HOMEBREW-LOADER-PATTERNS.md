# PS4 homebrew loader patterns

Reference for **PS4 Linux** (`CSTP00003`) and regression tests in `PkgLayoutGuard`.

## Pattern A — unified `eboot.bin` (what we ship)

Used by OpenOrbis samples, Apollo (~6.5 MiB eboot on console), OneFamily (~878 KiB), GoldHEN Cheat Manager, etc.

1. Link **all** app objects → one `eboot.elf` with `link.x`, `crt1.o`, and every `-lSce*` / `-lc` you need.
2. `create-fself` with **`--paid 0x3800000000000011 --authinfo=…`** → **`eboot.bin`** (FSELF `4F153D1D`). Mac builds use **`create-fself-macos`**.
3. PKG includes **`sce_module/libc.prx`**, **`libSceFios2.prx`**, **`sce_sys/about/right.prx`**, assets.
4. Library launch → **kernel loader** applies **`PT_SCE_DYNLIBDATA`**, resolves PLT/`JUMP_SLOT`, runs **`main()`**.

**PS4 Linux Makefile:** `$(MENU_OBJS) -o $(ODIR)/eboot.elf $(LDFLAGS)` — no secondary menu binary.

Measured on user hardware (FTP PKG extract):

| App | `eboot.bin` size |
|-----|------------------|
| OneFamily companion | ~878 KiB |
| Apollo | ~6.5 MiB |
| PS4 Linux (unified) | ~1.5–2 MiB expected |

Large eboots **do not** imply CE-41839-5; that error is usually **invalid/corrupt SELF or PKG** ([scene reports](https://www.reddit.com/r/ps4homebrew/comments/fjbkmy/help_with_creating_game_backups/)).

## Pattern B — Payload Guest dual FSELF (not used here)

Tiny `eboot.bin` + **`guest.elf`** FSELF; chain **`sceSystemServiceLoadExec`**. GoldHEN sometimes reports wrong **`st_size`** on secondary FSELF → broken LoadExec.

## Pattern C — split plain ELF (removed)

Tiny eboot + **`guest.oelf`** + **`guestPlainLoaderRun()`** (manual mmap + relocs). Caused **CE-34878-0** when PLT was incomplete. **Do not ship again.**

## Regression guards (Mac tests)

| Error | Guard |
|-------|--------|
| **CE-34878-0** | Boot log: `loader: running` without `app: guest main entered`; Makefile/boot log must not show `guestPlainLoaderRun` |
| **Split chain** | `eboot.bin` &lt; 512 KiB; `guest.oelf` in tree or gp4 |
| **CE-41839-5** | **CSTP00003 GoldHEN:** ship **OneFamily profile** only — **8-entry** `@0x18=0x220008`, **`0x3D0/0x3D0` @0x0C**, **`@0x70=0x60`**, **`eboot.bin` ≤ 950 KiB** (`FselfShipGate.validateGoldHenOneFamilyShipProfile`). Reject 10-entry ~1.6 MiB create-fself and python repack. |
| **CE-30008-1** | `validatePkgIntegrity` (no 0-byte gp4 files, no **3200 B** eboot); log `30008` / `size=3200` |

## Logging after unified eboot

- **`BootTrace`** constructor writes **`RUN START`** before `main`.
- **`main()`** logs `eboot: unified OpenOrbis eboot` and **`step: 00`**.
- Success on hardware: **`app: guest main entered`**, **`step: 10`…`21`**.

Legacy sources **`ChainLauncher.c`** / **`GuestPlainLoader.c`** remain in repo for history but are **excluded from the link**.
