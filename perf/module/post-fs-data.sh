#!/system/bin/sh
# Runs early (post-fs-data). Apply only the vm sysctls now so flash-write
# behaviour is sane from early boot. ZRAM + governor are deferred to service.sh
# (after boot) where the system's own init has already settled, so we win last
# and the zram swapoff/reconfigure happens on a quiet device.
MODDIR=${0%/*}
export MODDIR
[ -f "$MODDIR/tune.sh" ] && sh "$MODDIR/tune.sh" early
exit 0
