#!/bin/sh
# platform: macOS-only -- the generated wrapper runs Apple's /usr/bin/clang
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
[ -x /usr/bin/clang ] || { echo "no /usr/bin/clang -- skipping"; exit 77; }
. "$R/build/versions.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/cross-cc-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
P="$T/usr/local/mavergreen/go-cross"
sh "$R/build/write-cross-cc.sh" "$P"
CC_="$P/bin/mavericks-cross-clang"
[ -x "$CC_" ] || fail "write-cross-cc.sh wrote no executable bin/mavericks-cross-clang"
mkdir -p "$P/lib"; : > "$P/lib/librecaulk.a"
printf '#include <AvailabilityMacros.h>\nint main(void){return 0;}\n' > "$T/hello.c"

ln -s ../sdk109/SDKs "$P/SDKs"
if "$CC_" -c "$T/hello.c" -o "$T/hello.o" > "$T/out" 2>&1; then fail "without sdk109 the wrapper must refuse"; fi
[ "$(cat "$T/out")" = "mavericks-cross-clang: run 'sudo longboat sdk install 10.9' (github.com/Mavergreen/longboat)" ] \
  || { cat "$T/out"; fail "without sdk109 the wrapper says, in one line, to run sudo longboat sdk install 10.9"; }

sdk="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
mkdir -p "$T/usr/local/mavergreen/sdk109/SDKs"; ln -s "$sdk" "$T/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk"
"$CC_" -c "$T/hello.c" -o "$T/hello.o" > "$T/out" 2>&1 || { cat "$T/out"; fail "with sdk109 installed beside the tree the wrapper must compile"; }
"$CC_" -### "$T/hello.o" -o "$T/hello" > "$T/link" 2>&1 || { cat "$T/link"; fail "the wrapper's link step must plan"; }
grep -q "\"-syslibroot\" \"$P/SDKs/MacOSX10.9.sdk\"" "$T/link" || { cat "$T/link"; fail "the link uses the SDK through the tree's SDKs link"; }
grep -q "\"$P/lib/librecaulk.a\"" "$T/link" || { cat "$T/link"; fail "the link step appends the tree's lib/librecaulk.a"; }
for s in $WLU_SYMS; do
  grep -q "\"-U\" \"$s\"" "$T/link" || { cat "$T/link"; fail "the link step allows $s undefined"; }
done
echo "PASS: cross-cc"
