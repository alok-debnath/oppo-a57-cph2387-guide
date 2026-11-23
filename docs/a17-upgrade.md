# Android 17 upgrade plan — Oppo A57 4G (CPH2387), GSI route

Status at write time (2026-11-23): files being staged tonight; **flashing is a morning task with the user.**
Current device: LineageOS 23.2 (Android 16) GSI `arm64_bgN4` + APatch root + perf module, all working
(WiFi/BT/GPS/root/perf). Goal: move to Android 17.

## What A17 GSI is available (checked 2026-11-23)

Android 17 reached stable 2026-06-16. LineageOS 24 (A17) released 2026-10-11.

- **No GApps-baked (`bgN`) A17 GSI yet** from the builders we trust (kkhunter2 — our A16 source — has only
  23.2; Andy Yan has no 24.x posted). This matters: our current A16 is GApps-baked, so Play Store "just works".
- **Only concrete A17 GSI = eyzner/LineageOS-GSI, `lineage-24.0-20261029`, VANILLA (`arm64_bvN`, no GApps).**
  - File: `lineage-24.0-20261029-UNOFFICIAL-arm64_bvN.img.xz` (ext4; non-erofs chosen to match our flashing path)
  - SHA256 (`.xz`): `e6096462437491afcd309638a7ff42ab4ff2255396f1bf225af0783b6f0ad703`
  - Staged in `gsi/` (verified + decompressed tonight).
- **MindTheGapps A17 arm64** staged too: `MindTheGapps-17.0.0-arm64-20261022_132445.zip` (~544 MB),
  from github.com/MindTheGapps/17.0.0-arm64. For the vanilla GSI if we want Play Store.

## The GApps problem (DECIDE IN MORNING)

Our boot is APatch-patched **stock** boot — there is **no LineageOS recovery** to `adb sideload` the MTG zip.
So MindTheGapps can't be flashed the normal way. Options, best first:

1. **Wait for a GApps-baked (`bgN`) A17 GSI** (kkhunter2 / Andy Yan will likely build one). Then the upgrade is a
   straight `system_a` flash exactly like the A16 one — no GApps dance. Lowest risk. Recommended if not urgent.
2. **Vanilla A17 now + offline-inject MindTheGapps** into the system image on the host before flashing
   (loop-mount the ext4 img, copy MTG `system/*` with correct contexts + `addon.d`, grow the image). Doable but
   fiddly (perms/sepolicy/size); test boot carefully.
3. **Vanilla A17 now, no Play Store** — use Aurora Store (+ microG if Google services needed). Simple, but not
   the same as GApps.
4. **Vanilla A17 + temporarily `fastboot boot` a compatible LineageOS 24 recovery**, then sideload MTG. We have no
   device-matched recovery image; a generic one may not boot. Least reliable here.

## Critical: data wipe + what survives

A major GSI version jump (A16 → A17) across ROM families usually **bootloops on a dirty /data** — plan for a
**factory reset (`fastboot -w` / wipe userdata)**. That wipes `/data`, which means:

- **APatch `apd` + modules (incl. our perf module) are in `/data/adb` → GONE after wipe.** Must re-setup.
- **APatch root grant → GONE.** Re-install the APatch app + re-enable AndroidPatch.
- **VoLTE module (when applied) → GONE.**

**Survives the wipe** (because it lives in `boot`, not `/data`):
- The APatch **kernel patch** (KernelPatch/kpimg) — so WiFi/BT/GPS vendor modules still load, and the superkey is
  still baked in. After wipe, re-install APatch APK → it auto-detects KernelPatch → tap AndroidPatch Install → done.
- Bootloader unlock, stock vendor partitions.

So the post-flash re-setup (morning) = reinstall APatch APK, re-install perf module (`perf/a57-lowram-perf-v0.1.zip`
via `apd module install`), reboot, re-verify. VoLTE + fingerprint are their own tracks.

## Flash flow (morning, with user)

1. Confirm A17 img + (if chosen) GApps staged & verified in `gsi/`.
2. `adb reboot fastboot` (fastbootd — needed for the dynamic `super` logical partitions).
3. Check active slot (`_a`) and free space. A16 needed deleting Oppo `my_*` bloat + resizing `system_a` to ~3.6 GB.
   Re-check A17 decompressed size; resize `system_a` to fit (see LOG.md A16 steps for the exact resize/delete recipe).
4. `fastboot flash system_a gsi/lineage-24.0-20261029-UNOFFICIAL-arm64_bvN.img`  (vbmeta already disabled).
5. If GApps via offline-inject: do it on the `.img` BEFORE step 4.
6. Factory reset: `fastboot -w` (wipes userdata) — expect this is required; try without only if willing to re-flash on bootloop.
7. `fastboot reboot`. First boot of a fresh GSI is slow (optimizing apps).
8. Boot verify: `wlan0` present, kernel still 4.19.191+ (APatch boot untouched), `ro.build.version.release`=17.
9. Re-setup root + perf: install APatch APK → AndroidPatch Install → `apd module install perf/...zip` → reboot → verify.

## Rollback (if A17 fails / bootloops and we can't fix fast)

- Re-flash the known-good A16 GSI: `fastboot flash system_a gsi/lineage-23.2-20261016-UNOFFICIAL-arm64_bgN4.img`
  (still staged), `fastboot -w`, reboot. Back to tonight's working state.
- Boot/kernel never changed, so no boot risk from the GSI swap itself. BROM is auth-free for any deeper recovery.

## Open risks to watch

- A17 GSI on an Android-13 (ColorOS 13) vendor: A16 GSI booted fine on this vendor, so A17 very likely boots too
  (Treble VINTF is backward-compatible), but it's not guaranteed — test, keep the A16 rollback ready.
- Fingerprint stays broken on A17 (same vendor.oplus HAL mismatch — unrelated to Android version). See
  `docs/fingerprint-gsi.md`.
- VoLTE: re-apply the module after the data wipe; still SIM-gated for testing.


## Staging result (2026-11-23, tonight)

- A17 GSI downloaded + SHA256 verified + decompressed: `gsi/lineage-24.0-20261029-UNOFFICIAL-arm64_bvN.img`
  = 2,400,296,960 bytes (2.40 GB, ext4 vanilla). `.xz` sha OK (e6096462...ad703).
- MindTheGapps: `gsi/MindTheGapps-17.0.0-arm64-20261022_132445.zip` (544 MB) + sha256 verified OK.
- A16 reference img (rollback) still staged: 3.50 GB `bgN4` (GApps). system_a was sized ~3.6 GB, so A17
  (2.40 GB vanilla, or ~3 GB MTG-injected) fits.
- **DECISION: A17 flash HELD for morning-with-user.** Reason: only vanilla A17 exists; keeping Play Store needs
  hand-injecting MTG (unbootable to validate offline) and the A16->A17 jump needs a /data wipe that destroys the
  now-working APatch root + perf. Flashing vanilla blind would regress a daily driver. Lower-risk paths: wait for a
  GApps-baked bgN A17 GSI (then it's a straight system_a flash), or do the guided upgrade together in the morning.
