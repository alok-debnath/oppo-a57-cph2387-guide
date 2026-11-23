# volte/ — candidate MTK IMS/VoLTE restore for an Android GSI

**Status: UNTESTED speculative prep.** No GSI has been flashed to the CPH2387
yet. This was built ahead of time from the stock `super` dump so the IMS blobs
are ready the moment a GSI is up. Nothing here has been run on the device.

## What this is

A16 (and A15) phh/TrebleDroid GSIs on MediaTek devices commonly lose VoLTE,
because a system-only GSI replaces `/system` and drops the stock MediaTek IMS
app, its framework jars and its `/system` libs. The vendor-side VoLTE stack
(daemons, RIL, HAL, configs) stays on the untouched `vendor` partition.

This folder packages the `/system` side back as a systemless KernelSU / Magisk
module, so VoLTE can register on the GSI without modifying the vendor partition.

- `module/` — module source tree (reviewable, diffable).
- `mtkimsvolte_cph2387-v0.1-UNTESTED.zip` — the same tree, flashable.
- `INVENTORY.md` — every carried file, its stock source path, purpose, SHA256.
- `module/README.md` — install steps and per-file detail.

All blobs come from the device's own stock firmware
(`CPH2387_13.1.1.200(EX01)`, Android 13 / ColorOS 13.1, 2023-06). This is
lawful personal work on owned hardware; the kernel source is officially
published by Oppo. These device blobs live in this **private** repo only — never
the public kernel repo.

## The method it is built to match (research, 2025/2026)

The current phh/TrebleDroid MTK VoLTE recipe, from the TrebleDroid issue tracker
and community MTK VoLTE fixes:

1. **Install the MTK IMS app** `com.mediatek.ims`. phh's Treble Settings has an
   "Install IMS APK" action that downloads a generic `ims-mtk-*.apk`. This module
   instead carries the device's **own** stock `ImsService.apk`, built against
   this exact modem/RIL — verified `com.mediatek.ims`,
   `sharedUserId=android.uid.phone`, `android.telephony.ims.ImsService`,
   `BIND_IMS_SERVICE`.
2. **Place it in `/system/priv-app`** (not a user install): it needs the system
   signature context and the `android.uid.phone` shared UID, which only a
   priv-app placement gives. A normal `pm install` fails on signature / UID.
3. **Whitelist its privileged permissions** via a privapp-permissions XML — AOSP
   GSIs enforce the allowlist, so this is mandatory, not optional.
4. **Set props** the phh telephony stack reads:
   `persist.sys.phh.ims.caf=true` and the `persist.dbg.*_avail_ovr` /
   `allow_ims_off` overrides. (The MTK `persist.vendor.*` IMS props are already
   live from the stock vendor partition a GSI does not touch.)
5. In phh Treble Settings, enable **"Request IMS Network"** and **"Force presence
   of 4G calling"** after boot.
6. **Incoming-call `+EAIC` caveat (vendor-side, not in this module):** phh
   rewrites `AT+EAIC=2`→`=3` in the vendor `libmtk-ril.so`. On several MTK A15
   GSIs that breaks incoming VoLTE calls (outgoing works, incoming goes to
   voicemail). Fix is to keep `EAIC=2`. Some units also need the IMS APN
   `profile_id = 2`. This module does not modify vendor, so it neither causes nor
   cures this — watch for it.

Sources consulted: TrebleDroid `treble_experimentations` issue #200 (MTK
incoming calls / `+EAIC`), `spyboxx/mediatek_volte_fix` (priv-app placement +
dbg props), the XDA "Fix VoLTE in PHH GSIs" thread, and the /e/OS GSI VoLTE
thread. All are a year or more old; the EAIC and profile_id points are the
freshest MTK-specific findings and are confirmed only on single other devices.

## How to flash (once a GSI is running, rooted)

1. Flash an A16 phh/TrebleDroid GSI (arm64, A/B, vndklite or standard) and boot.
2. Root with KernelSU or Magisk.
3. Install `mtkimsvolte_cph2387-v0.1-UNTESTED.zip` in the root manager. Reboot.
4. Settings → enable VoLTE; in phh Treble Settings enable "Request IMS Network"
   and "Force presence of 4G calling".
5. Verify (see `module/README.md`): `pm list packages | grep com.mediatek.ims`,
   `dumpsys activity services com.mediatek.ims`, `logcat -b radio | grep -iE
   "ims|volte|EAIC"`, and watch for the VoLTE/HD icon.

## Assumptions and what to verify once a GSI boots

- **Assumed:** the GSI is system-only; vendor/odm/system_ext/product stay stock,
  so the vendor VoLTE daemons/libs/HAL and the MTK `persist.vendor.*` props are
  all present. If the GSI image also overlays those, more would need restoring —
  re-check `INVENTORY.md`'s vendor-side list.
- **Uncertain — the big one:** whether the **stock** `com.mediatek.ims` app runs
  on a pure AOSP GSI without the MTK framework jars. phh ships a *rebuilt*
  `ims-mtk` app for exactly this reason. If the stock app throws
  `ClassNotFoundException` for `mediatek-ims-*` classes in logcat, fall back to
  phh's downloaded `ims-mtk-*.apk` (swap it into `system/priv-app/ImsService/`),
  keeping this module's allowlist and props. The MTK framework jars are in
  `module/extras/framework/` for reference but must **not** be dropped into
  `system/framework` on an AOSP GSI (bootloop risk).
- **Uncertain:** the `+EAIC`/incoming-call behavior and whether IMS APN
  `profile_id` needs to be 2 on this unit — only testable on a booted GSI.
- **Not included:** IMS **video** (ViLTE). `libimsma` + its `/system/lib64` chain
  are in `module/extras/lib64/` but the chain is GSI-replaced and fragile; voice
  VoLTE does not need them.
- **Not yet known:** whether the A16 GSI even breaks VoLTE on this device. If a
  given GSI keeps VoLTE working out of the box, this module is unnecessary.

## Provenance

Extracted with `lpunpack.py` (liblp split) + `erofs-utils` `fsck.erofs
--extract` from `backup/dump-2026-11-22/super.bin`, slot `_a`. The large raw
images are not committed (see repo `.gitignore`). Carried files' SHA256 are in
`INVENTORY.md`; `ImsService.apk` was byte-verified identical to its source in
`super`.
