# Where we are (stop the layout loop)

**Internal agent runbook:** `tmp/docs/PS4-LINUX-INTERNAL-RUNBOOK.md`

**psxitarch desktop policy:** `docs/PS4-PSXITARCH-BEST-PRACTICES.md` — apply with `apply-psxitarch-best-practices-ps4.sh` (JWM Ubuntu path until `Arch.img` is fsck’d).

## What kept going in circles

| Symptom | We tried | What it actually was |
|--------|----------|----------------------|
| Package Installer problems | Split tiny `eboot` | Often **“already installed”** (APP_VER / GoldHEN background install), not CE-41839 |
| Assumed **CE-41839** = big eboot | Split layout | **Apollo ~6.5 MiB eboot** installs on the same PS4; size was a red herring |
| App blue screen / instant exit | Plain `guest.oelf` loader | **CE-34878-0** — manual PLT loader, confirmed in logs |
| Fix loader / LoadExec again | More chain variants | OpenOrbis apps use **one unified `eboot.bin`**; we were reimplementing the kernel linker |

**Decision (locked in Makefile + `PkgLayoutGuard` tests):** ship **only unified `eboot.bin`**. Tests **fail** if split chain or `guest.oelf` returns.

We will **not** split the binary again unless Package Installer shows **CE-41839-5 on a fresh install of unified PKG** with evidence — then we fix **create-fself / PKG**, not architecture.

## Your console right now (check anytime)

```bash
swift tools/ps4-linux-console-cycle.swift status
```

Typical states:

1. **Installed, empty log** — open **Library → PS4 Linux** once (not an install error).
2. **`app: guest main entered`** — layout is solved; any remaining bugs are app code (graphics, pad, Linux payload).
3. **`loader: running`** — stale **split** build; delete tile, install latest **`PS4-Linux-v*.pkg`**.

## One hardware gate

After each Mac build:

1. Delete old tile if switching from split builds (0.7.56–0.7.58).
2. Install latest `PS4-Linux-v*.pkg` from `/data/pkg/`.
3. Launch once.
4. `swift tools/ps4-linux-console-cycle.swift logs`

Mac tests cannot replace step 3.
