# Bootloader unlock — Oppo A57 4G (CPH2387 / OP5355, MT6765) — WORKING RECIPE

Status: **UNLOCKED, confirmed 2026-11-22** (`fastboot getvar unlocked` = `yes`,
`unlock_critical` = `yes`). This device is unlockable for free via a patched preloader.
CPH2387 is **not** in the Shocked-Cat support list, but the method works on it.

## What does NOT work
- `mtk.py da seccfg unlock`: writes a valid unlocked seccfg (state byte 0x01->0x03, hash
  recomputed — verified by reading seccfg back), BUT **Oppo's LK ignores seccfg**. After reboot the
  device still reports `flash.locked=1`, `verifiedbootstate=green`. Flashing a modified boot while
  locked => RED state ("current image destroyed"). Do not use the seccfg route.
- Official Oppo "in-depth/Deep Testing" unlock app: mainland-China models only. CPH2387 (global)
  is not eligible. (Realme's In-Depth Test covers India; Oppo's does not.)
- The AOSP "OEM unlocking" toggle in Developer options: necessary but NOT sufficient on its own.

## What works — patched preloader -> fastboot flashing unlock

Prereqs: full partition backup done (esp. stock `preloader_boot0.bin`), OEM unlocking ON,
mtkclient working, BROM reachable (auth-free on this unit: power off, hold Vol-Up+Vol-Down, plug
USB while holding; start mtkclient waiting FIRST).

1. Dump the stock preloader (eMMC boot0) if not already backed up:
   ```
   python mtk.py rf preloader_boot0.bin --parttype=boot1
   ```
2. Patch it (host only, no device writes). Tool: Shocked-Cat/oppo-mtk-fastboot-unlock.
   ```
   cp preloader_boot0.bin boot1.bin
   python3 -I path_preloader.py boot1.bin
   # -> preloader_path/boot1.bin ; log shows: EMMC_BOOT, lock state 0x22 (lock),
   #    Fastboot lock state: 0x22 -> 00 ; size stays 4194304. (~251KB differ = payload relocation.)
   ```
3. Write the patched preloader back (active slot _a -> boot1; slot _b -> boot2):
   ```
   python mtk.py wf preloader_path/boot1.bin --parttype=boot1
   python mtk.py reset        # unplug, power on
   ```
4. Boot Android, then:
   ```
   adb reboot bootloader       # reaches UNLOCKED fastboot (patch opened it)
   fastboot devices            # should list the device as "fastboot"
   fastboot getvar unlocked    # "no" at this point
   fastboot flashing unlock    # -> "Start unlock flow"; CONFIRM ON PHONE (Volume to select, Power)
   ```
   Confirming WIPES userdata and unlocks.
5. Verify before flashing anything custom:
   ```
   fastboot getvar unlocked         # want: yes
   fastboot getvar unlock_critical  # want: yes
   ```

## Flash custom (only after unlocked = yes)
```
fastboot flash vbmeta_a kernel-flash/vbmeta-disabled_a.img
fastboot flash boot_a   kernel-flash/boot-ksu_a.img
fastboot reboot
```
(Use the active slot's suffix. `getvar current-slot` returns "unknown command" on this LK; slot was
`_a`. Partition-size-0 / skip-avb-footer warnings are normal here; writes still succeed.)

## Recovery if anything goes wrong
- Bad preloader / no power-on: re-enter BROM, `python mtk.py wf backup/dump-2026-11-22/preloader_boot0.bin --parttype=boot1`.
- Red state / bad boot: restore stock `boot_<slot>.bin` + `vbmeta_<slot>.bin` from backup via BROM or
  (now unlocked) fastboot.
- BROM is auth-free, so every software brick above is recoverable.

## Why the earlier research was too pessimistic
A delegated research pass concluded "no free unlock" (seccfg broken per mtkclient #228 + Oppo token
gate + CPH2387 not in support list + 4G siblings fail). Two of those held (seccfg ignored; official
app closed), but the preloader-patch DID open fastboot on this exact model. Same-chip siblings split:
A17/A17K/A55 work, A15/A35/A54 fail — CPH2387 lands in the working group.
