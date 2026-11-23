#!/sbin/sh
# APatch / Magisk / KernelSU install script. No files go into /system. At boot,
# post-fs-data.sh bind-mounts descriptor-patched interface libraries (staged in
# files/) over their /odm/lib64 paths. This script only prints guidance and sets
# permissions.
ui_print "- Oplus Biometrics HIDL Descriptor Shim $(grep_prop version $MODPATH/module.prop)"
ui_print "- Makes an AOSP GSI bind the oplus fingerprint/face HAL by renaming the"
ui_print "  HIDL interface descriptor in the vendor interface library."
if [ ! -f "$MODPATH/files/vendor.oplus.hardware.biometrics.fingerprint@2.1.so" ]; then
  ui_print " "
  ui_print "  !! WIP: no patched .so staged in files/. This module is INERT."
  ui_print "  !! Pull /odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so,"
  ui_print "  !! patch it with tools/patch_hidl_descriptor.py, place the result in"
  ui_print "  !! files/, rebuild the zip (build.sh), then reflash. See README.md."
  ui_print " "
fi
ui_print "- Nothing applied until reboot. Remove the module + reboot to fully undo."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755 0755
