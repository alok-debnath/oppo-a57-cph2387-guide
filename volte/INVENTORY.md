# VoLTE/IMS inventory — CPH2387 stock extraction

Source firmware: `CPH2387_13.1.1.200(EX01)`, Android 13 / ColorOS 13.1,
MediaTek MT6765 (Helio G35), build date 2023-06-14/15.

Extracted from the local dump `backup/dump-2026-11-22/super.bin` (RAW liblp
super, slot `_a`). The dynamic partitions are **EROFS** (not ext4).

Tooling used: standalone `lpunpack.py` to split `super` per partition, then
`erofs-utils` `fsck.erofs --extract` to unpack each EROFS image. FUSE mount was
not permitted in the work environment, so images were fully extracted and then
deleted to stay within the disk budget.

## How a system-only GSI changes the picture

A phh/TrebleDroid GSI replaces **`system`** only. `vendor`, `odm`, `system_ext`
and `product` stay stock. So every vendor-side VoLTE component below survives on
the device untouched; what is lost is the `/system` side (the IMS app, the MTK
framework jars, the IMS media libs, and the `/system` props). The module
restores the `/system` side only.

## Bundled into the module (the `/system` side that a GSI removes)

| File (module path) | Source partition : path | Purpose | SHA256 |
|---|---|---|---|
| `system/priv-app/ImsService/ImsService.apk` | system : `/system/priv-app/ImsService/ImsService.apk` | The MTK IMS app `com.mediatek.ims` (`sharedUserId=android.uid.phone`, implements `android.telephony.ims.ImsService`, `BIND_IMS_SERVICE`). Core of VoLTE. | `824a6c8a…de9743a` |
| `system/etc/permissions/privapp-permissions-mediatek-ims.xml` | system : `/system/etc/permissions/privapp-permissions-mediatek.xml` (only the `com.mediatek.ims` block, extracted verbatim) | Privileged-permission allowlist. AOSP GSI enforces it; missing ⇒ permission denial / bootloop. | `a263664f…ce1f01d` |
| `system/etc/permissions/android.hardware.telephony.ims.xml` | vendor : `/vendor/etc/permissions/android.hardware.telephony.ims.xml` | Declares `android.hardware.telephony.ims` feature. Already on stock vendor; shipped as a safety net. | `6f0d8f1e…666dadd` |
| `system/etc/sysconfig/com.mediatek.ims.config.xml` | system : `/system/etc/sysconfig/com.mediatek.ims.config.xml` | Lets `com.mediatek.ims` ignore location settings (stock GMS config). | `031208e1…918f50b7f` |

Props set by `system.prop`: `persist.sys.phh.ims.caf=true`,
`persist.dbg.allow_ims_off=1`, `persist.dbg.volte_avail_ovr=1`,
`persist.dbg.vt_avail_ovr=1`, `persist.dbg.wfc_avail_ovr=1`.

## Opt-in extras (bundled under `module/extras/`, NOT auto-installed)

| File | Source | Why opt-in |
|---|---|---|
| `extras/framework/ims-common.jar` | system : `/system/framework/` | Needs BOOTCLASSPATH; mixing stock MTK framework jars with AOSP framework usually bootloops. |
| `extras/framework/mediatek-ims-base.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-ims-common.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-ims-extension-plugin.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-telephony-common.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-telephony-base.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-common.jar` | system : `/system/framework/` | " |
| `extras/framework/mediatek-carrier-config-manager.jar` | system : `/system/framework/` | " |
| `extras/lib64/libimsma.so` | system : `/system/lib64/` | IMS **video** (ViLTE) media adaptation. Core voice VoLTE does not use it. |
| `extras/lib64/libimsma_adapt.so` | system : `/system/lib64/` | libimsma dependency. |
| `extras/lib64/libimsma_rtp.so` | system : `/system/lib64/` | libimsma RTP dependency. |
| `extras/lib64/libimsma_socketwrapper.so` | system : `/system/lib64/` | libimsma dependency. |
| `extras/lib64/libsink.so` | system : `/system/lib64/` | libimsma media dependency. |
| `extras/lib64/libsource.so` | system : `/system/lib64/` | libimsma media dependency. |
| `extras/lib64/libvcodec_cap.so` | system : `/system/lib64/` | libimsma video-codec-cap dependency. |
| `extras/lib64/libcomutils.so` | system : `/system/lib64/` | libimsma dependency. |
| `extras/lib64/libsignal.so` | system : `/system/lib64/` | libimsma dependency. |

`libimsma` NEEDED chain was confirmed with `readelf -d`: standard AOSP libs
(`libbinder`, `libmedia`, `libstagefright`, `libgui`, `libui`, ...) plus the
MTK libs above, all of which live in `/system/lib64` and are therefore
GSI-replaced. That is why the VT path is impractical to restore from a module.

## Vendor-side VoLTE components that stay STOCK (NOT bundled — kept on device)

These remain on the untouched `vendor`/`odm`/`system_ext`/`product` partitions
when a system-only GSI is flashed. Listed here so the full stack is documented.

vendor (`/vendor`):
- Daemons `/vendor/bin/`: `volte_stack`, `volte_ua`, `volte_imcb`,
  `volte_imsm_93`, `volte_md_status`, `volte_clientapi_ua`, `volte_rcs_ua`,
  `rcs_volte_stack`.
- init: `/vendor/etc/init/init.volte_*.rc`, `volte_clientapi_ua.rc`.
- libs `/vendor/lib[64]/`: `libmtkrilutils.so`, `libcarrierconfig.so`,
  `libipsec_ims_shr.so`, `librcs_interface.so`, `librcs_volte_core.so`,
  `libvolte_core_shr.so`, `libvolte_xdmc_shr.so`,
  `vendor.mediatek.hardware.rcs@2.0.so`.
- configs: `/vendor/etc/virtual-spn-conf-by-imsi.xml`.

odm (`/odm`): `vendor.oplus.hardware.ims-V1.0-java.jar`,
`vendor.oplus.hardware.ims@1.0.so`, `overlay/CarrierConfigOverlay.21334.apk`.

system_ext (`/system_ext`): `priv-app/MtkCarrierConfig/MtkCarrierConfig.apk`,
`etc/permissions/com.android.carrierconfig.xml`.

product (`/product`): `overlay/OplusCarrierConfig.apk`,
`etc/permissions/com.android.imsserviceentitlement.xml`.

my_region: `etc/oplus_carrier_config.xml`.

## Relevant stock props (already live from stock vendor on a GSI)

From `/vendor/build.prop` (persist, survive GSI flash):
`persist.vendor.volte_support=1`, `persist.vendor.mtk.volte.enable=1`,
`persist.vendor.ims_support=1`, `persist.vendor.mims_support=2`,
`persist.vendor.vilte_support=1`, `persist.vendor.mtk_wfc_support=1`,
`persist.vendor.mtk_ct_volte_support=3`,
`persist.vendor.mtk_dynamic_ims_switch=1`, `ro.vendor.md_auto_setup_ims=1`,
`ro.telephony.iwlan_operation_mode=AP-assisted`.

From `/system/build.prop`: `persist.vendor.wfc.sys_wfc_support=1`.
From `/system_ext/etc/build.prop`: `persist.radio.hvolte.enable=1`.
