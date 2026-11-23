#!/sbin/sh
# KernelSU / Magisk install script. No files are copied into /system; all tuning
# is done at runtime by post-fs-data.sh + service.sh and via system.prop. This
# script only prints guidance and makes the scripts executable.
ui_print "- A57 Low-RAM Performance Tuner v0.1 (CPH2387 / MT6765 / 4GB)"
ui_print "- Conservative, reversible: zstd ZRAM ~2GB, swappiness 120,"
ui_print "  PSI-based LMKD low-RAM props, flash-friendly vm ratios, schedutil."
ui_print "- Nothing applied until reboot. Remove the module + reboot to fully undo."
ui_print "- Verify after reboot: see README (zramctl, getprop ro.lmk.*, etc.)."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/tune.sh" 0 0 0755 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755 0755
