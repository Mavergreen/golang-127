#!/bin/sh
# platform: host-agnostic
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
# Every carried change says when to reconsider it (spec decision 4): each '### <patch>.patch'
# section must contain a line matching '*Reconsider' before the next '### ' or '## ' heading.
awk '
  /^### .*\.patch$/ { if (name != "") report(); name = $0; has = 0; next }
  /^## / { if (name != "") report(); name = ""; next }
  name != "" && /Reconsider/ { has = 1 }
  END { if (name != "") report() }
  function report() { if (!has) { print "FAIL: " name " has no *Reconsider* line -- every carried change says when to reconsider it (spec decision 4)"; fail_seen = 1 } }
  END { if (fail_seen) exit 1 }
' "$R/PORT.md" || fail=1
[ "$fail" = 0 ] || exit 1
echo "PASS: port-md"
