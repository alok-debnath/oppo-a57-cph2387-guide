# a57-lowram-perf — low-RAM performance tuner (CPH2387 / MT6765 Helio G35 / 4 GB)

A flashable KernelSU/Magisk module that performance-tunes the Oppo A57 4G running
an Android 16 GSI (LineageOS 23.x) with root. All tuning is **runtime** (per the
`docs/plan.md` decision), not in the kernel. Everything is **conservative,
reversible, idempotent and fully guarded** — a bad value cannot brick the device,
and removing the module + rebooting restores stock behaviour.

- Module id: `a57_lowram_perf`
- Package: `perf/a57-lowram-perf-v0.1.zip`
- Status: **v0.1 — UNAPPLIED / UNTESTED** (pending WiFi fix, then apply + measure on hardware)

## Layout

```
module.prop                         id, version, author
system.prop                         LMKD (ro.lmk.*) props, applied by resetprop at post-fs-data
post-fs-data.sh                     early: vm sysctls only
service.sh                          late (after boot): full tune (vm + zram + governor)
tune.sh                             shared, guarded tuning routine
customize.sh                        install-time ui_print + perms
META-INF/com/google/android/
  update-binary                     stock Magisk module template
  updater-script                    "#MAGISK"
```

## What each knob does, the value chosen, and why (4 GB / G35)

### 1. ZRAM — zstd, ~2 GiB (`tune.sh` `setup_zram`)
- **What:** a compressed RAM block device used as swap. Pages that would be killed
  or paged to slow eMMC are instead compressed in RAM. zstd gives a better
  compression ratio than lz4, so more effective RAM, at a modest CPU cost — a good
  trade on a RAM-starved device where the G35's cores are otherwise idle.
- **Value:** `disksize = 2147483648` (2 GiB ≈ 50% of 4 GB RAM), `comp_algorithm = zstd`
  (falls back to `lz4`, then kernel default, if zstd is unavailable in this kernel).
- **Why 50%:** on 4 GB, ~2 GB zram with zstd (~2.5–3x ratio) yields roughly
  5–6 GB of effective capacity without starving uncompressed working set. Larger
  (1.5–2x RAM) is possible but less conservative for a daily driver; 50% is the
  safe starting point, adjust after measuring.
- **Robustness:** handles zram0 already in use — if the GSI already swapped it on,
  the script `swapoff`s, `reset`s, re-sets algorithm+size, `mkswap`, `swapon`
  (priority 32758). If already exactly 2 GiB and active, it no-ops. If zram0 is
  busy and swapoff fails, it leaves zram untouched (never forces).

### 2. vm sysctls (`tune.sh` `apply_vm`)
- `vm.swappiness = 120` — zram-backed swap is cheap (RAM, not disk), so a **high**
  swappiness is correct: prefer compressing cold pages over killing apps. Chosen in
  the 100–130 band. (Note: this is contested — some phone communities prefer low
  swappiness ~20 on the theory that mobile CPUs pay more for compression and the
  HAL prefers killing. The plan's decision is high; **verify empirically** whether
  120 or a lower value feels better on this hardware.)
- `vm.vfs_cache_pressure = 50` — keep dentry/inode cache a bit longer (vs default
  100) so repeated file lookups don't re-hit slow storage. Mild.
- `vm.dirty_background_ratio = 5`, `vm.dirty_ratio = 20` — flush dirty pages sooner
  and in smaller bursts, which is gentler on slow eMMC and avoids big writeback
  stalls. Modest, not aggressive.
- `vm.page-cluster = 0` — disable swap read-ahead clustering. zram decompresses
  per-page, so reading neighbouring pages on swap-in only wastes CPU/latency. This
  is a standard zram tuning.

### 3. LMKD — PSI-based props (`system.prop`, i.e. `ro.lmk.*`)
Modern Android (10+, and this A16 GSI) runs lmkd in **PSI mode** by default; the
in-kernel minfree driver is legacy. Rather than write `minfree` levels directly
(fighting the newer model), we set the **AOSP-documented low-RAM reference values**
as props, **without** setting `ro.config.low_ram` (that would broadly change system
behaviour and disable features — too heavy / not "conservative"):

| Prop | Value | Why (vs AOSP high-perf default) |
|---|---|---|
| `ro.lmk.use_psi` | `true` | keep PSI monitors (default) |
| `ro.lmk.use_minfree_levels` | `false` | do NOT use the legacy free-mem/filecache strategy |
| `ro.lmk.swap_free_low_percentage` | `10` | low-RAM default (HP 20): treat swap as starved at 10% |
| `ro.lmk.thrashing_limit` | `30` | low-RAM default (HP 100): react to pagecache thrashing sooner |
| `ro.lmk.thrashing_limit_decay` | `50` | low-RAM default (HP 10) |
| `ro.lmk.psi_partial_stall_ms` | `200` | low-RAM default (HP 70): fewer premature kills under expected pressure |
| `ro.lmk.psi_complete_stall_ms` | `700` | AOSP default |

Reference: <https://source.android.com/docs/core/perf/lmkd>.
Note: Android 16 also ships a newer memory-management daemon (`mmd`); on this
4.19-kernel GSI lmkd is the active killer, so these props are the right lever. If a
future build switches to mmd, revisit.

### 4. CPU governor — schedutil (`tune.sh` `setup_governor`)
- **What:** sets `scaling_governor` on **every** cpufreq policy
  (`/sys/devices/system/cpu/cpufreq/policy*/scaling_governor`).
- **Value:** `schedutil` if available, else `interactive`, else `ondemand`.
- **Why:** schedutil is driven directly by the scheduler's utilization signal, so
  it ramps frequency more responsively/efficiently than the older governors — good
  for perceived snappiness on a weak SoC. The MT6765/G35 stock 4.19 kernel usually
  exposes schedutil; the fallbacks cover kernels that don't.
- **Safety:** governor only. We do **NOT** lock, cap or raise max/min frequency, and
  there is no undervolt/underclock.

## How to verify after apply (on the device)

```sh
# ZRAM: should show zram0, zstd, ~2G
zramctl
cat /proc/swaps
cat /sys/block/zram0/comp_algorithm   # [zstd] in brackets = active
cat /sys/block/zram0/disksize         # 2147483648

# LMKD props
getprop | grep ro.lmk
# or individually: getprop ro.lmk.swap_free_low_percentage  etc.

# vm sysctls
cat /proc/sys/vm/swappiness            # 120
cat /proc/sys/vm/vfs_cache_pressure    # 50
cat /proc/sys/vm/dirty_ratio           # 20
cat /proc/sys/vm/page-cluster          # 0

# CPU governor (each policy)
for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo "$p: $(cat $p)"; done

# memory overview
free -h

# what the module actually did this boot:
cat /data/adb/modules/a57_lowram_perf/last-apply.log
```

## How to roll back

1. Open the KernelSU / Magisk manager, **remove** the `a57_lowram_perf` module.
2. **Reboot.**

That reverts everything: `ro.lmk.*` props go back to platform defaults (system.prop
no longer applied), vm sysctls return to kernel/init defaults, zram returns to the
GSI's own configuration, and the governor returns to the platform default. Nothing
is written to `/system` or persisted outside the module, so removal is complete.

To disable without removing: toggle the module off in the manager and reboot.

## Device-specific uncertainty to confirm on hardware

- Whether **zram0 pre-exists / is already swapped on** by the GSI (expected yes) —
  the script handles both, but confirm the reconfigure took (`zramctl`).
- Whether this kernel exposes **zstd** in `comp_algorithm` (fallback is lz4).
- Whether **schedutil** is in `scaling_available_governors` (fallback interactive/ondemand).
- Whether **swappiness 120** actually feels better than a lower value — measure.
