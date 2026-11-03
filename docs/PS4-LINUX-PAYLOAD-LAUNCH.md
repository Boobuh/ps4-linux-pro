# PS4 Linux — “failed to launch payload” (0x1) / instant power-off

Symptoms you hit: **first try → failed to launch payload 0x1**; **second try → console off** (needs mains or long power-button reset).

Boot files on **`/data/linux/boot/`** are fine; the failure is usually **how** the loader payload is run, **GoldHEN version**, **VRAM**, or **AutoRun** — not missing `bzImage`.

---

## 1. Do this before the next attempt

1. **Cold boot** PS4 (wall power if it hung), load **GoldHEN**.
2. **Turn off OneFamily AutoRun** (loads another payload at boot and can break Linux tries):
   - GoldHEN → **Payloads** → disable **AutoRun** for `onefamily.bin`, **or**
   - FTP: set `/data/GoldHEN/payloads.ini` `[AutoRun]` entry to `0` (we apply `1024` stack when FTP is up).
3. **Unplug all USB storage** (sticks/HDDs). Loader uses USB kernel files if any USB disk is present.
4. **Do not** open **Android TV**.
5. Check **GoldHEN version** in the menu:
   - **Avoid 2.4b18.8** (broken Linux payloads — [GoldHEN #340](https://github.com/GoldHEN/GoldHEN/issues/340)).
   - Prefer **2.4b18.10+** (ELF payload fix — PayLoader LaunchPad).

---

## 2. Launch method (important)

| Method | Use |
| --- | --- |
| **GoldHEN → Utilities → PayLoader → LaunchPad** | Pick **`linux-1024mb.elf`** — **best** on current GoldHEN |
| **Payload Guest** | Needs **`.bin`**, not `.elf` — use **`linux-1024mb.bin`** (copy of same loader) |
| **BinLoader / empty TCP to 9090** | **Wrong** for this — that’s for BinLoader clients (Android TV), not the kexec loader file |
| **WebKitty** ([webkitty](http://webkitty.arabpixel.net)) | Cache once, **Linux** tab, **11.00**, **1GB VRAM** payload |

Do **not** use **`payload-1100-4gb-pro-baikal.bin`** until a **1GB rescue boot works**. DionKill: first install / first boot → **1GB VRAM or less**.

---

## 3. VRAM must match payload

| File | `vram.txt` in `/data/linux/boot/` |
| --- | ---: |
| `linux-1024mb.elf` / `.bin` | **1024** |
| `linux-2048mb.elf` | **2048** |
| `payload-1100-1gb-pro-baikal.bin` | **1024** |

Mismatch can crash or “fail to launch”.

---

## 4. After power-off on second attempt

That’s often **payload crash during kexec** (not a bad FTP upload). Sequence:

1. Mains reset → GoldHEN again.
2. **Only** PayLoader → **`linux-1024mb.elf`** once.
3. Wait **3–5 min** on black HDMI (Bravia may drop CEC).
4. Success = **text rescue shell**. Still dead = kernel path issue (next: different bzImage / report).

---

## 5. When FTP is on again (Mac)

We push the safe set:

```bash
PS4=10.0.1.7
DIR=/path/to/ps4-linux-pro/downloads/ps4-linux-baikal
curl -T "$DIR/vram.txt" "ftp://${PS4}:2121/data/linux/boot/vram.txt"
curl -T "$DIR/linux-1024mb.elf" "ftp://${PS4}:2121/data/payloads/linux-1024mb.elf"
curl -T "$DIR/linux-1024mb.bin" "ftp://${PS4}:2121/data/payloads/linux-1024mb.bin"
```

Say **“FTP on”** and we’ll run that plus disable OneFamily AutoRun in `payloads.ini` if you want.

---

## 6. What 0x1 usually means

GoldHEN **rejected or crashed running the loader payload** before Linux starts — not “kernel missing on disk”. Common fixes: **PayLoader + .elf**, **GoldHEN ≥ b18.10**, **1GB VRAM**, **no AutoRun payload**, **no b18.8**.

Boot files on console: **feeRnt** `bzImage` + **Nazky** `initramfs.cpio.gz` (has **`install-HDD.sh`**) under `/data/linux/boot/`; **`arch.tar.xz`** under **`/user/system/boot/`** — **internal HDD only**, no USB stick.

---

## 7. Internal install (no USB)

After rescue shell (`/#`):

```text
exec install-HDD.sh
```

Enter how many GB for Linux; wait (long on stock HDD). Finish with **`exec start-arch.sh`** or **Ctrl+D** if it does not auto-boot.

Do **not** use hippie68’s **`exec install-psxitarch.sh`** — that path expects a FAT USB stick with the tarball on it.
