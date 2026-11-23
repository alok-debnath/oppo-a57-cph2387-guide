# Plan

## Goals

1. Full backup of every partition before any write.
2. Unlock the bootloader.
3. Root: Magisk on stock first, then a custom kernel with KernelSU-Next and SUSFS.
4. Custom ROM: The Clover Project, if it can be made to run.

## Feasibility (2026-11-22)

| Goal | Status | Notes |
|---|---|---|
| Unlock | Probably possible with mtkclient | No official Oppo unlock. Community reports CPH2387 on Android 13 unlocked with mtkclient `seccfg unlock`. One GSM-Forum report of a device dying after an unlock attempt. |
| Root | Possible | Magisk-patched `boot` is the simplest first step. |
| SUSFS kernel | Possible, manual work | Upstream SUSFS has a `kernel-4.19` branch (last update 2025-02-23). Non-GKI kernel, so KernelSU-Next with manual hooks. Patches will likely need fixups. |
| Clover ROM | Not directly | Clover is Android 17 (`-b 17`, `cp2a`). Official devices: alioth, asteroids, onyx, peridot, rodin. No Oppo, no MT6765, no GSI target. No OP5355 device tree exists. Build needs ~500 GB disk and ~64 GB RAM. |

## Phases

1. Backup: mtkclient full dump except `userdata`, eMMC boot areas, GPT, SHA-256 hashes.
2. Unlock with mtkclient. Check boot, `oplusreserve1` flag, verified boot state.
3. Magisk on stock `boot` to prove the boot chain works.
4. Build kernel from the T branch, add KernelSU-Next and SUSFS, flash `boot`.
5. Test an existing TrebleDroid-based GSI on the stock vendor.
6. Only if 5 works well: port Clover as a GSI on a cloud build machine.

## Risks

- "Download not completed" on boot after flashing via mtkclient: bootloader checks a flag in
  `oplusreserve1`. Restore from backup.
- Losing `nvram` / `nvdata` without a backup loses the IMEI permanently.
- Relocking with non-stock images hard-bricks the phone.
- Flashing older stock partitions can trip rollback protection.
- Custom kernel vs stock vendor modules: version/symbol mismatch can stop modules loading
  (Wi-Fi `wlan_drv_gen4m`, BT, etc.).
- Android 17 on a 4.19 kernel with a VNDK 31 vendor and 4 GB RAM may hit missing kernel features.

## Build host

Local PC: 15 GB RAM, 12 threads, 39 GB free on `/home`. Fine for a kernel build. Not enough
for a full ROM build.

## Decided strategy (2026-11-22)

ROM = GSI, not a device-specific build. Kept on the stock 4.19 kernel (only kernel with working
GPU/camera/modem for MT6765; newer kernel = dead hardware). A16 system via phh Treble shims.

- ROM: LineageOS 23.2 A16 GSI (arm64 A/B), boot-tested first.
- VoLTE: not guaranteed on MTK GSI. Experiment = port stock MTK IMS (ims.apk + configs from our
  super.bin) via phh "Install IMS apk". If VoLTE can't be fixed and it's non-negotiable, A16 GSI
  is not viable -> stay stock for VoLTE.
- Root/stealth: KernelSU-Next in a rebuilt 4.19 kernel (+ SUSFS if the 4.19 port holds). Magisk
  first as the smoke test.
- Performance on 4 GB / G35: tune the 4.19 kernel (ZRAM, LMKD, governor), not a newer kernel.
- Device tree from scratch / Clover: not pursued now (MTK bring-up is months, VoLTE/camera
  uncertain). Revisit only as a project.

## Performance tuning — module built v0.1, pending apply (2026-11-23)

Status: runtime tuning module built — `perf/a57-lowram-perf-v0.1.zip` (id `a57_lowram_perf`).
UNAPPLIED/UNTESTED, pending WiFi fix, then flash + measure on hardware. See `perf/README.md`.

Not in the kernel build. The big low-spec wins are runtime, tuned empirically on the final ROM:
- ZRAM size + zstd/lz4, swappiness, LMKD thresholds, CPU governor — applied via a KSU/Magisk module
  or init props AFTER the GSI boots, then measured/adjusted on the 4 GB / G35 hardware.
- Undervolt: skipped (risky, device-specific).
- Kernel only needs to SUPPORT ZRAM (stock config already does); no perf config baked into the build.
