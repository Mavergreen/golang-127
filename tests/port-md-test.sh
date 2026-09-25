#!/bin/sh
# Every carried change is explained in PORT.md, and PORT.md explains nothing that is not carried.
# A change whose reason lives only in gitignored docs gets quietly undone at the next port -- go127's
# port nearly dropped two deliberate trust decisions exactly that way.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$R/PORT.md" ] || { echo "FAIL: no PORT.md -- every carried change needs its reason tracked"; exit 1; }
fail=0
for p in "$R"/patches/*.patch; do
  b="$(basename "$p")"
  grep -q "^### $b\$" "$R/PORT.md" || { echo "FAIL: PORT.md has no '### $b' section"; fail=1; }
done
for b in $(sed -n 's/^### \(.*\.patch\)$/\1/p' "$R/PORT.md"); do
  [ -f "$R/patches/$b" ] || { echo "FAIL: PORT.md explains $b, which is not in patches/"; fail=1; }
done
[ "$fail" = 0 ] || exit 1
echo "PASS: port-md"
