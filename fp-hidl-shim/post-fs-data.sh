#!/system/bin/sh
# post-fs-data: runs BEFORE the late_start fps_hal service, so the bind-mount is
# in place before the oplus service dlopen()s its interface library.
#
# Mechanism: for each descriptor-patched interface library staged in
# $MODDIR/files, bind-mount it over the stock /odm/lib64 path. The patched .so
# registers and answers to the AOSP descriptor instead of the oplus one, so the
# GSI framework can bind the HAL.
#
# EVERY step is guarded so this can never fail boot. If files/ is empty (the WIP
# default) this script is a complete no-op.

MODDIR=${0%/*}
LOG="$MODDIR/shim.log"
echo "=== fp_hidl_shim post-fs-data $(date 2>/dev/null) ===" > "$LOG" 2>/dev/null

# bind_over <staged_src_basename> <target_abs_path>
bind_over() {
  src="$MODDIR/files/$1"
  tgt="$2"
  if [ ! -f "$src" ]; then
    echo "skip: staged $src absent" >> "$LOG" 2>/dev/null
    return 0
  fi
  if [ ! -f "$tgt" ]; then
    echo "skip: target $tgt absent" >> "$LOG" 2>/dev/null
    return 0
  fi
  # copy the target's exact SELinux context onto the replacement
  tgtctx=$(ls -Zd "$tgt" 2>/dev/null | awk '{print $1}')
  [ -n "$tgtctx" ] && chcon "$tgtctx" "$src" 2>>"$LOG"
  chmod 0644 "$src" 2>>"$LOG"
  if mount -o bind "$src" "$tgt" 2>>"$LOG"; then
    echo "bound: $src -> $tgt (ctx=$tgtctx)" >> "$LOG" 2>/dev/null
  else
    echo "FAILED bind: $src -> $tgt" >> "$LOG" 2>/dev/null
  fi
  return 0
}

# Fingerprint: the generated HIDL interface library carries the descriptor.
bind_over "vendor.oplus.hardware.biometrics.fingerprint@2.1.so" \
          "/odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so"

# Face: ONLY if on-device inspection shows the face HAL is HIDL vendor.oplus.
# The host-pulled face-service is AIDL and already uses the AOSP descriptor
# (android.hardware.biometrics.face.IFace), so by default there is nothing to
# bind. Left here, inert, for the HIDL-face case.
bind_over "vendor.oplus.hardware.biometrics.face@1.0.so" \
          "/odm/lib64/vendor.oplus.hardware.biometrics.face@1.0.so"

exit 0
