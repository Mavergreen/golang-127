#!/bin/sh
# platform: macOS-only -- pkgutil unpacks the Recaulk .pkg, and lipo reads the archive's slices
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
: "${RECAULK_VERSION:?set RECAULK_VERSION}"

OUT="$WORK/recaulk"
A="$OUT/lib/librecaulk.a"
root="$WORK/recaulk-tree"
sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" recaulk "$RECAULK_VERSION" "$root" >/dev/null
[ -f "$root/lib/librecaulk.a" ] || { echo "FATAL: no lib/librecaulk.a in the dev.mavergreen.recaulk payload" >&2; exit 1; }
[ -d "$root/include/recaulk" ] || { echo "FATAL: no include/recaulk in the dev.mavergreen.recaulk payload" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT/lib" "$OUT/include"
cp "$root/lib/librecaulk.a" "$OUT/lib/"
cp -R "$root/include/recaulk" "$OUT/include/"

lipo -info "$A" 2>/dev/null | sed -n 's/.*: //p' | grep -qw x86_64 \
  || { echo "FATAL: $A has no x86_64 slice (archs: $(lipo -info "$A" 2>&1 | sed -n 's/.*: //p'))" >&2; exit 1; }

echo "$A"
