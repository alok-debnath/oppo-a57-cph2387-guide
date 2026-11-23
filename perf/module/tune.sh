#!/system/bin/sh
# a57_lowram_perf — shared runtime tuning routine.
#
# Called by post-fs-data.sh (early: vm sysctls only) and service.sh (late: full
# tune incl. ZRAM + governor). Every action is guarded with existence/writable
# checks and `|| true`, so a missing node or a bad value can NEVER fail the boot.
# Everything here is idempotent: re-running it just re-asserts the same state.
#
# Args: $1 = "early" (sysctls only) or "full" (sysctls + zram + governor)

MODDIR=${MODDIR:-/data/adb/modules/a57_lowram_perf}
LOG="$MODDIR/last-apply.log"
PHASE="${1:-full}"

log() { echo "$(date '+%H:%M:%S') [$PHASE] $*" >> "$LOG" 2>/dev/null; }

# ---- helpers ---------------------------------------------------------------

# write VALUE to /proc/sys/PATH if it exists and is writable
set_sysctl() {
  node="/proc/sys/$1"
  [ -w "$node" ] || { log "skip sysctl $1 (absent/ro)"; return 0; }
  echo "$2" > "$node" 2>/dev/null && log "sysctl $1=$2" || log "FAIL sysctl $1=$2"
}

# ---- vm sysctls ------------------------------------------------------------
apply_vm() {
  # zram-backed swap is cheap -> high swappiness is correct. 100-130 band.
  set_sysctl vm/swappiness 120
  # keep more dentry/inode cache -> fewer storage re-reads (mild, 50 vs def 100).
  set_sysctl vm/vfs_cache_pressure 50
  # flush dirty pages sooner in smaller bursts -> smoother on slow eMMC.
  set_sysctl vm/dirty_background_ratio 5
  set_sysctl vm/dirty_ratio 20
  # for zram, disable swap read-ahead clustering: decompress is per-page, so
  # reading neighbours just wastes CPU/latency.
  set_sysctl vm/page-cluster 0
}

# ---- ZRAM ------------------------------------------------------------------
# Target ~50% of 4 GB RAM. 2 GiB = 2147483648 bytes.
ZRAM_SIZE=2147483648

zram_dev() {
  # resolve the block node (Android uses /dev/block/zram0)
  for d in /dev/block/zram0 /dev/zram0; do [ -e "$d" ] && { echo "$d"; return; }; done
  echo ""
}

setup_zram() {
  SYS=/sys/block/zram0
  [ -d "$SYS" ] || { log "no zram0 sysfs, skip zram"; return 0; }
  DEV="$(zram_dev)"
  [ -n "$DEV" ] || { log "no zram0 block node, skip zram"; return 0; }

  # already exactly our size and active? idempotent no-op.
  cur_size="$(cat "$SYS/disksize" 2>/dev/null)"
  if [ "$cur_size" = "$ZRAM_SIZE" ] && grep -q "zram0" /proc/swaps 2>/dev/null; then
    log "zram0 already $ZRAM_SIZE and swapped on, leave as is"
    return 0
  fi

  # turn off existing swap on zram0 if the GSI already brought it up
  if grep -q "zram0" /proc/swaps 2>/dev/null; then
    swapoff "$DEV" 2>/dev/null && log "swapoff $DEV" || { log "swapoff busy, leave zram as is"; return 0; }
  fi

  # reset so disksize/comp_algorithm can be rewritten
  echo 1 > "$SYS/reset" 2>/dev/null && log "reset zram0" || log "reset failed (non-fatal)"

  # pick compression: prefer zstd, else lz4, else whatever is default
  if [ -w "$SYS/comp_algorithm" ]; then
    avail="$(cat "$SYS/comp_algorithm" 2>/dev/null)"
    for alg in zstd lz4; do
      case " $avail " in
        *" $alg "*|*"[$alg]"*)
          echo "$alg" > "$SYS/comp_algorithm" 2>/dev/null && log "comp_algorithm=$alg" && break ;;
      esac
    done
  fi

  # size (must be set after algorithm; initialises the device)
  echo "$ZRAM_SIZE" > "$SYS/disksize" 2>/dev/null && log "disksize=$ZRAM_SIZE" \
    || { log "disksize set FAILED, abort zram"; return 0; }

  # format + enable, high priority so it is actually used
  mkswap "$DEV" >/dev/null 2>&1 && log "mkswap $DEV ok" || log "mkswap FAILED"
  swapon -p 32758 "$DEV" 2>/dev/null || swapon "$DEV" 2>/dev/null
  if grep -q "zram0" /proc/swaps 2>/dev/null; then log "swapon $DEV ok"; else log "swapon FAILED"; fi
}

# ---- CPU governor ----------------------------------------------------------
# schedutil preferred, else interactive, else ondemand. Never touch max freq.
setup_governor() {
  base=/sys/devices/system/cpu/cpufreq
  [ -d "$base" ] || { log "no cpufreq, skip governor"; return 0; }
  for p in "$base"/policy*; do
    gov="$p/scaling_governor"
    [ -w "$gov" ] || continue
    avail="$(cat "$p/scaling_available_governors" 2>/dev/null)"
    for want in schedutil interactive ondemand; do
      case " $avail " in
        *" $want "*)
          echo "$want" > "$gov" 2>/dev/null && log "$(basename "$p") governor=$want"
          break ;;
      esac
    done
  done
}

# ---- power: battery/thermal, no perf cost ----------------------------------
# Battery wins that NEVER cap peak performance:
#   * enable every CPU cpuidle state -> cores reach deep idle between bursts
#     (default on, but some vendor init disables the deepest C-states; re-enable).
#   * set the GPU devfreq governor to simple_ondemand -> the GPU scales DOWN to
#     its min when idle instead of parking high. Max GPU freq is NEVER touched,
#     so peak graphics performance is unchanged.
# We deliberately do NOT alter thermal zones, max CPU freq, or max GPU freq:
# those would trade away the smoothness we just tuned for.
setup_power() {
  # re-enable all cpuidle states (deep idle = less power at rest)
  n=0
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    [ -w "$s" ] || continue
    echo 0 > "$s" 2>/dev/null && n=$((n + 1))
  done
  [ "$n" -gt 0 ] && log "cpuidle: re-enabled $n state nodes" || log "cpuidle: no writable state nodes"

  # GPU devfreq idle scaling. Mali on MT6765 exposes a devfreq node; the exact
  # path varies, so scan. simple_ondemand scales to min when idle, max under load.
  for gpu in /sys/class/devfreq/*; do
    [ -d "$gpu" ] || continue
    name="$(basename "$gpu")"
    case "$name" in
      *gpufreq*|*mali*|*gpu*|13000000.mali|*.mali)
        gov="$gpu/governor"
        [ -w "$gov" ] || continue
        avail="$(cat "$gpu/available_governors" 2>/dev/null)"
        case " $avail " in
          *" simple_ondemand "*)
            echo simple_ondemand > "$gov" 2>/dev/null && log "GPU $name governor=simple_ondemand" ;;
          *) log "GPU $name: simple_ondemand unavailable ($avail)" ;;
        esac ;;
    esac
  done
}

# ---- run -------------------------------------------------------------------
# early phase runs first at boot: start a fresh log. full phase appends.
[ "$PHASE" = "early" ] && : > "$LOG" 2>/dev/null
log "tune.sh start (phase=$PHASE)"
apply_vm
if [ "$PHASE" = "full" ]; then
  setup_zram
  setup_governor
  setup_power
fi
log "tune.sh done"
exit 0
