# Oplus Biometrics HIDL Descriptor Shim (`fp_hidl_shim`)

APatch / Magisk module for the Oppo A57 4G (CPH2387 / OP5355, MT6765) running an
AOSP GSI (Evolution X, Android 16) with APatch root. Goal: make Settings show
fingerprint (and, if applicable, face) enrollment by bridging the ColorOS HIDL
package-name mismatch.

Status: **v0.1-wip — currently inert.** Host-only analysis is complete and it
changed the plan (see "What the analysis found"). The module needs one more file
pulled from the device before it does anything. Flashing it as-is is a safe
no-op.

---

## The problem (recap)

The GSI framework calls `getService` for
`android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default`.
The device only serves ColorOS's renamed fork,
`vendor.oplus.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default`.
HIDL binds by descriptor string (the binder interface token), so the two never
connect → "Fingerprint HAL not available", no enrollment. See
`../docs/fingerprint-gsi.md` for the full diagnosis and rejected alternatives.

## The intended mechanism: descriptor byte-patch

The oplus interface is a renamed fork of AOSP `@2.1`. If the fork is a *clean*
rename (identical method table and transaction-code ordering), we can rewrite
the descriptor string so the oplus service both **registers** and **answers to**
the AOSP name. Then the framework binds it directly. No proxy process, no
sepolicy change (see below), no new init service.

The AOSP package token is 5 bytes shorter than the oplus one:

```
vendor.oplus.hardware.biometrics.fingerprint@2.1   (48 bytes)
android.hardware.biometrics.fingerprint@2.1        (43 bytes)
```

so the descriptor can be rewritten **in place**: write the shorter string, its
NUL terminator, then NUL-pad the 5 freed tail bytes. File size is unchanged, no
ELF offset or relocation moves. `tools/patch_hidl_descriptor.py` does exactly
this and refuses to touch `.so` library names or mangled C++ symbols.

## What the analysis found (host-only, 2026-11-23) — this changed the plan

Two binaries were pulled and analysed on the host. **Neither is the right file
to patch.**

### Fingerprint — descriptor is in the `.so`, not the `-service` binary

`/odm/bin/hw/vendor.oplus.hardware.biometrics.fingerprint@2.1-service`
(519768 bytes, arm64) does **not** contain the descriptor string at all. The
only `vendor.oplus...fingerprint` string in it is the **library dependency name**
`vendor.oplus.hardware.biometrics.fingerprint@2.1.so` — which must NOT be
patched. Confirmed with `readelf --dyn-syms`:

```
UND  _ZN6vendor5oplus...IBiometricsFingerprint17registerAsService...
UND  _ZN6vendor5oplus...IBiometricsFingerprint19interfaceDescriptor...
```

`registerAsService` and the descriptor are **imported** (UND) from the generated
interface library. The descriptor constant
`vendor::oplus::...::IBiometricsFingerprint::descriptor` lives in:

```
/odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so   <-- PATCH THIS
```

That `.so` was **not** pulled, so no working patched artifact exists yet.

Encouraging sign for the "clean rename" bet: the `-service` binary links **both**
`vendor.oplus...@2.1.so` **and** `android.hardware.biometrics.fingerprint@2.1.so`,
`@2.2.so`, `@2.3.so`, and carries the full AOSP `V2_1`/`V2_2`/`V2_3`
`IBiometricsFingerprint` IBase boilerplate symbols (`ping`, `interfaceChain`,
`getHashChain`, `interfaceDescriptor`, …) identical to the oplus ones. That is
consistent with a plain rename. It does **not** by itself prove the core method
ordering (`setNotify`/`preEnroll`/`enroll`/`authenticate`/…) matches AOSP — that
must be confirmed on-device (see Risks).

### Face — the pulled service is AIDL and already AOSP-named

`/odm/bin/hw/vendor.oplus.hardware.biometrics.face@1.0-service` (243456 bytes)
despite its filename is an **AIDL** service, not HIDL `@1.0`. It contains only
`aidl::android::hardware::biometrics::face::*` symbols, links
`android.hardware.biometrics.face-V1-ndk_platform.so`, and registers via
`AServiceManager_addService` under descriptor
`android.hardware.biometrics.face.IFace` — which is **already the AOSP name** the
GSI expects. There is no `vendor.oplus...face` string anywhere in it to rename.

So the face half of the original plan does not apply to this binary. Either face
already registers correctly (and any face failure has a different cause), or the
HIDL `vendor.oplus...face@1.0` the diagnosis referred to is served by a
*different* binary. This must be re-checked on-device before any face patch.

## How to finish the fingerprint fix

1. On the device, pull the interface library (the host cannot — host-only task):
   ```
   adb pull /odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so
   ```
   (Also check `/odm/lib/` for a 32-bit copy; the service is 64-bit so lib64 is
   what matters.)
2. Patch it on the host:
   ```
   python3 -I tools/patch_hidl_descriptor.py \
     vendor.oplus.hardware.biometrics.fingerprint@2.1.so \
     files/vendor.oplus.hardware.biometrics.fingerprint@2.1.so
   ```
   Expect it to report patching the descriptor string(s) with "size unchanged".
3. Rebuild and flash:
   ```
   ./build.sh
   apd module install fp-hidl-shim-*.zip   # (or Magisk)
   reboot
   ```

At boot, `post-fs-data.sh` (runs before the `late_start` `fps_hal` service)
copies the target's SELinux context onto the patched `.so`, `chmod 0644`s it, and
`mount -o bind`s it over `/odm/lib64/...`. When the oplus service starts and
`dlopen`s the library, it now registers the AOSP descriptor.

## Why no sepolicy or VINTF change should be needed

- `hwservice_contexts` maps **both** `android.hardware.biometrics.fingerprint`
  and `vendor.oplus.hardware.biometrics.fingerprint` to the **same** type
  `hal_fingerprint_hwservice`, so the service's domain already has `add` on the
  AOSP name and `system_server` already has `find`.
- The device VINTF manifest already declares
  `android.hardware.biometrics.fingerprint` (hidl/hwbinder, IBiometricsFingerprint,
  instance `default`) with `override="true"`.

If registration of the `@2.1` name is rejected because the manifest only
advertises `@2.3`, add a VINTF fragment declaring `@2.1` and bind-mount it into
`/odm/etc/vintf/manifest/`. Not included yet — add only if a denial/vintf error
proves it necessary.

## Verify after flashing

```
# the AOSP-named interface should now be registered:
lshal | grep -i biometrics.fingerprint
# expect: android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default
dumpsys fingerprint          # Fps state should be non-zero / HAL present
logcat -d | grep -i fingerprint   # no "Fingerprint HAL not available"
```
Then Settings → Security → Fingerprint should offer enrollment.

## Roll back

Remove the module (`apd module uninstall fp_hidl_shim` or delete it in the
manager) and reboot. The bind-mount is boot-scoped; nothing is written outside
the module directory, so reboot restores the stock `/odm/lib64` library.

## Risks / uncertainties to watch on-device

1. **Clean-rename assumption (highest risk).** Only proven for the IBase
   boilerplate. If oplus added or reordered methods vs AOSP `@2.1`, the AOSP
   framework's transaction codes map to the wrong oplus methods → crash or
   misbehaviour. Confirm on-device: `lshal -i` / compare `getHashChain` /
   interfaceChain of the oplus interface against AOSP `@2.1`. If they differ, a
   descriptor patch is unsafe — fall back to a forwarding proxy (Option 3 in
   `../docs/fingerprint-gsi.md`).
2. **The `.so` may hold more than one descriptor copy** (e.g. `interfaceChain`
   returns the chain of descriptors). The patcher rewrites *every* matching
   descriptor string; verify with `strings` before/after that only descriptor
   strings changed and the `.so` dependency names and symbols are untouched.
3. **Manifest `@2.3` vs registered `@2.1`** — if the framework or
   `hwservicemanager` rejects the `@2.1` registration, add the VINTF fragment.
4. **The oplus service may gate callers** (expect a specific oplus client UID/
   context, or depend on `fingerprintpay` / oplus framework pieces). If so, even
   a correct descriptor patch returns errors to the AOSP framework.
5. **Face** — re-confirm on-device what actually serves face
   (`lshal | grep -i face`) before touching anything; the pulled binary is AIDL
   and already AOSP-named.
