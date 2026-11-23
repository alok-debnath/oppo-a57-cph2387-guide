# Fingerprint on the Android 16 GSI (Oppo A57 4G, CPH2387 / OP5355)

Device: Oppo A57 4G, CPH2387 / OP5355, MediaTek MT6765 (Helio G35), side/capacitive
(power-button) fingerprint, NOT under-display/FOD. Stock vendor = ColorOS 13 (Android 13 base).
GSI = LineageOS 23.x / phh-treble lineage, treble, arm64 A/B. Root = APatch (Magisk-module
compatible, overlayfs, /system/bin/su).

## The problem, restated

Fingerprint enrollment is missing in Settings because the GSI framework cannot reach a fingerprint
HAL it understands.

- The AOSP framework binds `android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default`.
- `hwservicemanager` reports that interface is NOT registered; lazy-start fails; logcat shows
  "Fingerprint HAL not available".
- The device only serves Oppo's proprietary interfaces:
  `vendor.oplus.hardware.biometrics.fingerprint@2.1-service` and
  `vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service`.
- These are a different HIDL package name, so the framework will not bind them.

This is the classic Oppo/Realme ColorOS-on-GSI fingerprint failure. It is a vendor-namespace
problem, not a sensor or permission problem.

## Why it breaks (the core technical fact)

Oppo renamed the fingerprint HAL package. AOSP ships
`android.hardware.biometrics.fingerprint@2.1`. Oppo ships a forked copy under their own namespace,
`vendor.oplus.hardware.biometrics.fingerprint@2.1`. The two almost certainly have the same methods
(it is a renamed fork), but HIDL identifies every interface by a fully-qualified descriptor string
of the form `package@version::Interface`. Every binder transaction carries that descriptor as its
interface token, and the server rejects a transaction whose token does not match. The framework
sends `android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint`; the Oppo service only
answers to `vendor.oplus.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint`. They never
connect.

phh's Treble scripts do NOT bridge this. The phh `rw-system.sh` only *detects* a fingerprint HAL
to decide whether to show or hide the fingerprint feature: it greps the vendor manifests for
`android.hardware.biometrics.fingerprint`, `vendor.oppo.hardware.biometrics.fingerprint`, and
`vendor.oplus.hardware.biometrics.fingerprint`, and if none is present it masks
`android.hardware.fingerprint.xml`. On this device the oplus entry *is* present, so phh leaves the
feature enabled, but there is still no AOSP-named HAL for the framework to bind. phh has no shim
and no HIDL-to-HIDL proxy for oplus biometrics. Its only oplus-related fingerprint props are FOD
and sensor-node fixes (see Option 1), none of which bridge the interface.

## Ranked options (easiest and safest first)

### Option 1 — Try the known phh fingerprint props (cheap, safe, low chance here)

Proven to help on *some* Realme/Oppo GSIs, but these address detection/cleanup and FOD, not the
HIDL namespace mismatch that is the confirmed root cause here. Low expectation of success, but zero
cost and fully reversible, so try first.

- `persist.sys.phh.fingerprint.nocleanup=true` — phh's documented fix for "fingerprint sensor not
  getting detected". Set via the phh Treble Settings app or `setprop`/`resetprop`.
- `persist.sys.phh.fod.bbk` — phh already force-sets this to `true` for OnePlus/RMX/CPH devices.
  This is for under-display (FOD) sensors. Your sensor is side/capacitive, so this prop is
  irrelevant at best and may cause a wrong FOD overlay. Consider setting
  `persist.sys.phh.fod.bbk=false` (or clearing it) to stop any FOD misbehaviour.
- If the Fingerprint settings page itself crashes, phh's wiki suggests disabling
  `com.google.android.setupwizard`.

How to apply without a reboot loop: use the phh Treble Settings "misc features" toggles, or set
props in a boot-time script. None of these registers an AOSP HAL, so by themselves they will not
make enroll appear if the HAL truly is unregistered — but rule them out first.

Proven vs speculative: the props are proven to exist and to help on other devices (phh wiki). That
they fix *this* device is speculative and, given the confirmed namespace mismatch, unlikely.
Risk: none. All reversible.

Sources:
- phh "Common Issues and fixes": https://github.com/phhusson/treble_experimentations/wiki/Common-Issues-and-fixes
- phh `rw-system.sh` (manifest detection + props): https://github.com/TrebleDroid/device_phh_treble/blob/android-14.0/rw-system.sh
- Realme 8 5G / Narzo 30 5G GSI page (vendor-version dependence): https://github.com/phhusson/treble_experimentations/wiki/Realme-8-5G---Narzo-30-5G

### Option 2 — Switch to a device-specific ROM or a vendor that works (most reliable if available)

The most reliable fix for oplus fingerprint is to NOT rely on the stock oplus HIDL service at all.
Device-specific LineageOS/Evolution-X builds for Oppo/OnePlus/Realme phones ship their own
fingerprint HAL (an `android.hardware.biometrics.fingerprint` AIDL/HIDL service) that `dlopen`s the
vendor's fingerprint blob directly through shim libraries, bypassing the oplus HIDL namespace. See
the Evolution-X `hardware_oplus` tree for how this is structured (shims + UDFPS extension).

The catch for CPH2387 specifically:
- There is no official LineageOS device tree for OP5355 / CPH2387 (confirmed in the project plan),
  so there is no ready-made device-specific build that does this for you.
- Community reports show Oppo/Realme side-fingerprint on GSIs tends to work only on an *older
  vendor* (e.g. Realme 8 5G: side FP works on RealmeUI 2.0 vendor, broke on RealmeUI 4). If an
  older (Android 12 / ColorOS 12-base) stock vendor exists for CPH2387, a GSI on that older vendor
  may expose fingerprint more readily. This is unverified for CPH2387 and would mean downgrading
  the vendor, which has its own modem/DRM risks.

Proven vs speculative: the device-specific-HAL approach is proven on other oplus phones; its
availability for CPH2387 is absent. The older-vendor angle is proven on a different Realme device,
speculative for CPH2387.
Risk: medium (vendor downgrade can break modem/VoLTE/DRM and trip rollback protection).

Sources:
- Evolution-X `hardware_oplus` fingerprint (device-specific shim model): https://git.evolution-x.org/Evolution-X-Devices/hardware_oplus/src/branch/vic/fingerprint
- Realme 8 5G GSI vendor-version note: https://github.com/phhusson/treble_experimentations/wiki/Realme-8-5G---Narzo-30-5G
- Oppo A5s GSI page (FP not working on GSI): https://github.com/phhusson/treble_experimentations/wiki/Oppo-A5s

### Option 3 — Write a small HIDL-to-HIDL shim service (the real fix; moderate effort)

This is the technically correct fix and is feasible precisely because the oplus interface is a
renamed fork of the AOSP interface. Build a tiny vendor service that:

1. Registers `android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default` (the
   name the framework wants).
2. On each call, forwards to
   `vendor.oplus.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default` (the service
   the device already runs).
3. Bridges the callback in reverse: the framework registers an
   `android...IBiometricsFingerprintClientCallback`; the shim must register an oplus callback with
   the real service and forward every `onEnrollResult`/`onAuthenticated`/`onError`/etc. back to the
   framework's callback.

Why it can work: the method tables match (renamed fork), so the forwarding is mostly mechanical,
one method per method, in both directions. HardwareAuthToken values are HMAC-signed by gatekeeper
and verified inside the TEE; as long as the GSI binds the same vendor gatekeeper HAL, tokens stay
valid through the shim.

Packaging as an APatch/Magisk module (no vendor repartition needed):
- A prebuilt 64-bit binary, e.g. `/system/bin/fingerprint-oplus-shim` (or dropped under the
  module's overlay).
- A VINTF manifest fragment declaring `android.hardware.biometrics.fingerprint@2.1` over hwbinder,
  instance `default`, installed where the framework's device-manifest compatibility check sees it
  (`/vendor/etc/vintf/manifest/...` via overlayfs, or `/odm/etc/vintf`).
- An `init.rc` service entry to start it (class hal, user system, the right groups), or run it as a
  lazy HAL.
- SELinux: a GSI typically runs enforcing. A new vendor domain needs policy. Practical shortcuts:
  run the shim in an existing permissive-friendly context, or ship an sepolicy patch via the
  module (APatch/Magisk can load a `sepolicy.rule`). This is the fiddliest part.

Hardest unknowns / risks:
- The oplus service may gate callers (expect a specific trusted client, or depend on the
  `fingerprintpay` service or oplus framework pieces). If it checks the caller UID/context, the
  shim must impersonate an accepted client.
- SELinux denials will block the shim until policy is right; expect iteration against
  `dmesg`/`audit2allow`.
- The callback bridge must match the exact oplus callback interface (likely
  `vendor.oplus.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprintClientCallback`); its
  method set must be confirmed from the device, not assumed.

Effort: a competent HIDL developer, a few days to a couple of weeks including SELinux and
debugging. It needs the device to iterate (we are RESEARCH-ONLY here, so this is a design, not a
build).

Published prior art: none found specifically for `vendor.oplus.hardware.biometrics.fingerprint`
HIDL-to-AOSP on a GSI. No XDA thread, GitHub repo, or Telegram guide turned up a ready-made oplus
biometrics HIDL proxy module. The closest existing work (Evolution-X/LineageOS `hardware_oplus`)
takes the different route of a device-specific HAL over the vendor blob, not a proxy over the oplus
HIDL service. So this shim would likely be new work.

Proven vs speculative: the *technique* (a thin HIDL passthrough proxy between two same-signature
interfaces) is sound and standard. That the oplus service accepts a proxy client, and that the
method tables are byte-compatible, is speculative until confirmed on-device (dump the oplus `.hal`
descriptors / run `lshal` and `vintf`).
Risk: medium. All of it is in the system/overlay layer and removable by deleting the module; no
partition writes. Worst realistic case is a non-booting GSI recoverable by removing the module.

Sources:
- AOSP Fingerprint HIDL (`IBiometricsFingerprint`, method list): https://source.android.com/docs/security/features/authentication/fingerprint-hal
- AOSP `IBiometricsFingerprint.hal` 2.1 source: https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/main/biometrics/fingerprint/2.1/
- HIDL architecture / descriptors / versioning: https://source.android.com/docs/core/architecture/hidl
- Evolution-X `hardware_oplus` fingerprint (shim reference): https://git.evolution-x.org/Evolution-X-Devices/hardware_oplus/src/branch/vic/fingerprint

### Option 4 — Aliasing / re-registering under the AOSP name (DOES NOT WORK; included for honesty)

Tempting idea: just re-register the already-running oplus binder under the AOSP name via an
`init.rc` line or an extra VINTF manifest entry, so the framework binds it directly. Assessed and
rejected.

- A VINTF manifest entry only advertises a name; it does not change which descriptor the running
  service answers to. Adding `android.hardware.biometrics.fingerprint@2.1` to the manifest while the
  only running service is the oplus one will make `hwservicemanager` report it, then the framework
  will try to transact and fail the interface-token check.
- You cannot register one binder object under a foreign interface name and have transactions
  succeed: HIDL's `readInterfaceToken` on the server side compares the incoming descriptor against
  the server's own descriptor and rejects a mismatch. The oplus service's descriptor is
  hard-compiled as `vendor.oplus...`, so an `android...` transaction fails regardless of how it was
  registered.
- Even if the method *layout* is identical, the token string differs, and that is what is checked.

Conclusion: there is no manifest/init.rc trick that makes the framework bind the oplus service
directly. A process that re-implements the AOSP descriptor and forwards (Option 3) is the minimum
that can work.

Proven vs speculative: the failure mode is a direct consequence of how HIDL binds, consistent with
the device's own logcat ("Fingerprint HAL not available" while the oplus service is up).
Risk: n/a (don't do it).

Sources:
- HIDL architecture (descriptor-based binding): https://source.android.com/docs/core/architecture/hidl
- Fingerprint HAL (interface identity): https://source.android.com/docs/security/features/authentication/fingerprint-hal

### Option 5 — Accept no fingerprint; use PIN/pattern/password (fallback)

If none of the above pays off, the GSI remains fully usable with a PIN, pattern, or password.
Face unlock is unlikely to work either (same vendor-namespace class of problem on ColorOS GSIs).
This is the zero-risk fallback and the honest default if the shim (Option 3) is not worth the time.

## Recommended path

1. Option 1 first: set `persist.sys.phh.fingerprint.nocleanup=true`, clear/`false` the FOD prop,
   check Settings. Minutes, reversible. (Low chance given the confirmed root cause.)
2. If a stock Android 12 / ColorOS 12-base vendor for CPH2387 exists and VoLTE/modem survive on it,
   test a GSI on that older vendor (Option 2). Medium risk.
3. If fingerprint matters enough to justify development, build the HIDL-to-HIDL shim (Option 3) as
   an APatch module: start by dumping the oplus `IBiometricsFingerprint` and callback descriptors
   and method tables on-device, confirm they mirror AOSP 2.1, then write the proxy + VINTF fragment
   + init.rc + sepolicy. This is new work; no published oplus-biometrics proxy exists to reuse.
4. Otherwise accept PIN/password (Option 5).

## What is proven vs speculative (summary)

- Proven: root cause is the HIDL package-name mismatch; phh has no bridge for it; aliasing cannot
  work; oplus GSIs commonly lose fingerprint and face unlock; device-specific HALs (not GSIs) are
  how oplus phones get working fingerprint.
- Speculative: that any phh prop fixes it here; that an older vendor exposes the sensor to a GSI;
  that the oplus service will accept a proxy client; the exact oplus method/callback tables (must be
  dumped on-device).

## Sources

- phh/TrebleDroid `rw-system.sh`: https://github.com/TrebleDroid/device_phh_treble/blob/android-14.0/rw-system.sh
- phh "Common Issues and fixes" wiki: https://github.com/phhusson/treble_experimentations/wiki/Common-Issues-and-fixes
- phh Realme 8 5G / Narzo 30 5G GSI page: https://github.com/phhusson/treble_experimentations/wiki/Realme-8-5G---Narzo-30-5G
- phh Oppo A5s GSI page: https://github.com/phhusson/treble_experimentations/wiki/Oppo-A5s
- AOSP Fingerprint HIDL: https://source.android.com/docs/security/features/authentication/fingerprint-hal
- AOSP `IBiometricsFingerprint.hal` 2.1: https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/main/biometrics/fingerprint/2.1/
- AOSP HIDL architecture: https://source.android.com/docs/core/architecture/hidl
- Evolution-X `hardware_oplus` fingerprint: https://git.evolution-x.org/Evolution-X-Devices/hardware_oplus/src/branch/vic/fingerprint
- ColorOS 12 fingerprint-fix precedent (safetynet-fix changelog): https://github.com/kdrag0n/safetynet-fix

## On-device test result (2026-11-23)

- **Option 1 (phh props) = FAILED, confirmed.** Set persist.sys.phh.fingerprint.nocleanup=true and
  persist.sys.phh.fod.bbk=false, rebooted. logcat still: "Fingerprint HAL not available"; dumpsys
  fingerprint Fps state=0. Props cannot bridge the HIDL namespace mismatch (as predicted). Props are
  harmless/correct (fod.bbk=false is right for a side sensor) — left in place; delete with
  `resetprop --delete persist.sys.phh.fingerprint.nocleanup` if desired.
- Services confirmed running: vendor.oplus.hardware.biometrics.fingerprint@2.1-service (pid varies),
  fingerprintpay@1.0-service, AND vendor.oplus.hardware.biometrics.face@1.0-service. `lshal` does not
  list them (lazy/renamed HAL) and no static vendor vintf fingerprint entry was found at the usual paths
  — consistent with the lazy-HAL / renamed-descriptor diagnosis.
- Implication: **face unlock is also dead** (same vendor.oplus namespace), matching the research note.
- Groundwork left for the shim build (Option 3): locate the HAL binary (not in /vendor/bin/hw — search
  /system, /odm, vendor dynamic), dump the oplus @2.1 interface descriptor + method order, then forward to
  the AOSP android.hardware.biometrics.fingerprint@2.1 name. Days of dev + on-device iteration; not done tonight.

## Binary-level analysis (2026-11-23, host-only) — descriptor byte-patch route

Pulled `vendor.oplus.hardware.biometrics.fingerprint@2.1-service` and
`vendor.oplus.hardware.biometrics.face@1.0-service` to the host and inspected
them (read-only; never executed). This refines Option 4 and adds a concrete
Option 6.

### Option 6 — rewrite the HIDL descriptor string in the interface `.so`

Because the oplus interface is a renamed fork, rewriting the descriptor constant
so the oplus service registers and answers to the AOSP token
(`android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint`) makes the
framework bind it directly — no proxy process. The AOSP package token is 5 bytes
shorter than the oplus one, so the string is rewritten in place (shorter string +
NUL + NUL-pad the freed tail), file size unchanged, no relocation moves. Tool:
`fp-hidl-shim/tools/patch_hidl_descriptor.py` (validated on a synthetic buffer:
patches the descriptor, leaves `.so` names and mangled symbols byte-identical).

This differs from the rejected Option 4 (aliasing): Option 4 only re-advertised a
name while the running service still answered the oplus token. Option 6 changes
the token the service itself serves, so the server-side `readInterfaceToken`
check passes.

### Key finding — the descriptor is NOT in the `-service` binaries

- **Fingerprint:** the `-service` executable does not contain the descriptor
  string. `readelf --dyn-syms` shows `IBiometricsFingerprint::registerAsService`
  and `::interfaceDescriptor` as **UND (imported)** — the descriptor constant
  lives in `/odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so`, which
  was not pulled. Patch that `.so`, not the service binary. The service links
  both the oplus `@2.1.so` and AOSP `@2.1/2.2/2.3.so` and carries identical IBase
  boilerplate for both namespaces — consistent with a clean rename, but the core
  method ordering is still unverified (confirm via on-device `lshal`/hashChain).
- **Face:** the pulled `...face@1.0-service` is actually an **AIDL** service
  (`aidl::android::hardware::biometrics::face`, `AServiceManager_addService`,
  deps `android.hardware.biometrics.face-V1-ndk_platform.so`). It already
  registers the AOSP descriptor `android.hardware.biometrics.face.IFace` — there
  is no `vendor.oplus...face` string to rename. Re-check on-device what serves
  face (`lshal | grep -i face`); the HIDL `@1.0` face mismatch does not apply to
  this binary.

### Next on-device step (host cannot do this)

`adb pull /odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so`, patch
with the tool above, stage into `fp-hidl-shim/files/`, `build.sh`, flash. Full
mechanism, verification and rollback in `fp-hidl-shim/README.md`.
