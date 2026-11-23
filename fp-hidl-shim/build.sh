#!/usr/bin/env bash
# Build the flashable module zip from this directory.
# Usage: ./build.sh   (run from the fp-hidl-shim/ directory or anywhere)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/fp-hidl-shim-$(grep '^version=' "$HERE/module.prop" | cut -d= -f2).zip"
cd "$HERE"
rm -f "$OUT"
# Zip everything the module needs; exclude build artefacts, VCS, logs, the
# host-side tools dir is included for reference but harmless on-device.
zip -r9 "$OUT" \
  module.prop customize.sh post-fs-data.sh uninstall.sh \
  META-INF files tools README.md \
  -x '*.zip' -x '*/.gitkeep' -x '*.log' >/dev/null
echo "built: $OUT"
unzip -l "$OUT"
