#!/system/bin/sh
# Runs late (late_start service class). Wait (bounded) for boot to complete, then
# do the full tune: re-assert vm sysctls, set up ZRAM robustly, set the governor.
# Applying after boot means we override whatever the GSI init set, and we
# reconfigure zram0 on a settled device instead of racing init.
MODDIR=${0%/*}
export MODDIR

# bounded wait for boot_completed (max ~60s); proceed anyway if it times out.
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do
  sleep 1
  i=$((i + 1))
done

[ -f "$MODDIR/tune.sh" ] && sh "$MODDIR/tune.sh" full
exit 0
