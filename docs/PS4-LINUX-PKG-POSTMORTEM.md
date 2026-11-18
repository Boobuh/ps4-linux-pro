## Canonical layout (unified eboot)

```
eboot.bin              # full UI FSELF (OpenOrbis standard, kernel dynlink)
sce_sys/param.sfo
sce_module/libc.prx, libSceFios2.prx
assets/...
```

See **`docs/PS4-HOMEBREW-LOADER-PATTERNS.md`**.

**Do not** ship split **`guest.oelf`** + tiny chain (**CE-34878-0**). **Do not** rely on LoadExec secondary menu FSELF (**st_size** bug on GoldHEN).

**CE-41839-5 (Cannot start application):** Usually bad install or stale tile — **Library → Delete PS4 Linux**, then install latest PKG. Unified eboot must be signed like Apollo: **`--paid 0x3800000000000011 --authinfo=…`** (not Payload-Guest chain-only). `param.sfo` **ATTRIBUTE=32**. Do not revert to split `guest.oelf`.

Runtime: Library → kernel loads **`eboot.bin`** → **`main()`** → **`app: guest main entered`**.
