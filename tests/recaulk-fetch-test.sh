#!/bin/sh
# platform: macOS-only -- pkgbuild, productbuild and pkgutil build and expand the fixture archive
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
command -v pkgbuild >/dev/null 2>&1 || { echo "SKIP: no pkgbuild"; exit 77; }
T="$(mktemp -d "${TMPDIR:-/tmp}/recaulk-fetch-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CC_="${CC:-cc}"
printf 'int recaulk_fixture(void){return 7;}\n' > "$T/fixture.c"
"$CC_" -arch x86_64 -c "$T/fixture.c" -o "$T/fixture.o" >/dev/null 2>&1 || { echo "SKIP: cannot build an x86_64 object"; exit 77; }

V="$(tr -d ' \t\r\n' < "$ROOT/components/recaulk/version")"
REL="$T/releases"; DIR="$REL/Mavergreen/recaulk/releases/download/$V"; PKG="recaulk-$V.pkg"; mkdir -p "$DIR"
P=usr/local/mavergreen/recaulk

mkdir -p "$T/base/usr/local/mavergreen/base/lib"; printf 'decoy\n' > "$T/base/usr/local/mavergreen/base/lib/librecaulk.a"
mkdir -p "$T/base/$P/lib"; printf 'decoy\n' > "$T/base/$P/lib/librecaulk.a"
pkgbuild --root "$T/base" --identifier dev.mavergreen.base --version 1 "$T/a-base.pkg" >/dev/null 2>&1

mkdir -p "$T/rc/$P/lib" "$T/rc/$P/include/recaulk"
ar rcs "$T/rc/$P/lib/librecaulk.a" "$T/fixture.o"
printf '/* fixture */\n' > "$T/rc/$P/include/recaulk/fixture.h"
pkgbuild --root "$T/rc" --identifier dev.mavergreen.recaulk --version 1 "$T/b-recaulk.pkg" >/dev/null 2>&1

productbuild --package "$T/a-base.pkg" --package "$T/b-recaulk.pkg" "$T/good.pkg" >/dev/null 2>&1
productbuild --package "$T/a-base.pkg" "$T/base-only.pkg" >/dev/null 2>&1

serve() { cp "$1" "$DIR/$PKG"; ( cd "$DIR" && shasum -a 256 "$PKG" > SHA256SUMS ); rm -rf "$T/work"; }
run() {
  MAVERGREEN_RELEASES="file://$REL" MAVERGREEN_PKG_CACHE="$T/work/pkgs" SHIPYARD_FETCH_BACKOFF=0 \
    MAVERICKS_WORK="$T/work" sh "$ROOT/build/fetch-recaulk.sh" >"$T/out" 2>"$T/err"
}
fail() { echo "FAIL: $1"; cat "$T/err" 2>/dev/null; exit 1; }
refused() { # $1 = what the stderr must name
  if run; then fail "accepted when it should name '$1'"; fi
  grep -q "$1" "$T/err" || fail "the refusal does not name '$1'"
}

serve "$T/good.pkg"
run || fail "the pinned archive must fetch"
lib="$(tail -n 1 "$T/out")"
cmp "$lib" "$T/rc/$P/lib/librecaulk.a" || fail "the extracted archive is not the dev.mavergreen.recaulk component's (the decoy?)"
[ -f "$T/work/recaulk/include/recaulk/fixture.h" ] || fail "include/recaulk was not extracted"

serve "$T/good.pkg"; : > "$DIR/SHA256SUMS"
refused 'not listed'

serve "$T/good.pkg"
run || fail "the pinned archive must fetch before the tamper case"
cached="$T/work/pkgs/recaulk/$V/$PKG"
[ -f "$cached" ] || fail "no cached pkg at $cached"
rm -rf "$T/work/recaulk-tree" "$T/work/recaulk-tree.stamp"
printf 'x' >> "$cached"
refused 'not the pinned'
[ ! -e "$cached" ] || fail "the tampered cached pkg must be removed"

serve "$T/base-only.pkg"
refused 'dev.mavergreen.recaulk'

variant() { # $1 = payload root, $2 = text the stderr must contain
  pkgbuild --root "$1" --identifier dev.mavergreen.recaulk --version 1 "$1.pkg" >/dev/null 2>&1
  productbuild --package "$T/a-base.pkg" --package "$1.pkg" "$1-product.pkg" >/dev/null 2>&1
  serve "$1-product.pkg"; refused "$2"
}
mkdir -p "$T/nolib/$P/include/recaulk"; printf '/* fixture */\n' > "$T/nolib/$P/include/recaulk/fixture.h"
variant "$T/nolib" 'no lib/librecaulk.a'
mkdir -p "$T/noinc/$P/lib"; cp "$T/rc/$P/lib/librecaulk.a" "$T/noinc/$P/lib/"
variant "$T/noinc" 'no include/recaulk'
if "$CC_" -arch i386 -c "$T/fixture.c" -o "$T/fixture32.o" >/dev/null 2>&1; then
  mkdir -p "$T/i386/$P/lib" "$T/i386/$P/include/recaulk"; ar rcs "$T/i386/$P/lib/librecaulk.a" "$T/fixture32.o"
  variant "$T/i386" 'no x86_64 slice'
else
  echo "NOTE: no non-x86_64 object here; the slice case is not exercised"
fi

echo "PASS: recaulk-fetch-test"
