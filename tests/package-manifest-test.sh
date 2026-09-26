#!/bin/sh
# platform: macOS-only -- pkgbuild, productbuild and PlistBuddy build and read the two archives
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
: "${SHIPYARD_SCRIPTS:=$R/../mavergreen-shipyard/scripts}"
[ -f "$SHIPYARD_SCRIPTS/stage_product.sh" ] || { echo "no shipyard with stage_product.sh at $SHIPYARD_SCRIPTS -- skipping" >&2; exit 77; }
command -v pkgbuild >/dev/null 2>&1 || { echo "no pkgbuild -- skipping" >&2; exit 77; }
export SHIPYARD_SCRIPTS
W="$(mktemp -d "${TMPDIR:-/tmp}/package-manifest.XXXXXX")"; trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
export MAVERICKS_WORK="$W/work" MAVERICKS_BUILD_ROOT="$W/build" UPD_APP="$W/no-updater.app"
. "$R/build/versions.sh"
mk() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod 755 "$1"; }
n="$WORK/staging$PREFIX"; c="$WORK/staging-cross$CROSS_PREFIX"
for f in bin/go bin/gofmt bin/mavericks-clang; do mk "$n/$f"; done
mkdir -p "$n/etc/openssl/certs"; : > "$n/etc/openssl/certs/ca-certificates.crt"
for f in bin/go bin/gofmt bin/mavericks-cross-clang; do mk "$c/$f"; done
sh "$R/build/package-pkg.sh" > "$W/native.log" 2>&1 || { cat "$W/native.log"; fail "the native archive must package from a staged tree"; }
sh "$R/build/package-cross-pkg.sh" > "$W/cross.log" 2>&1 || { cat "$W/cross.log"; fail "the cross archive must package from a staged tree"; }
V="$W/vol"; mkdir -p "$V"
for p in "$WORK"/out/golang-*-native-*.pkg "$WORK"/out/golang-*-cross-*.pkg; do
  [ -f "$p" ] || fail "no archive at $p"
  x="$W/x-$(basename "$p")"; pkgutil --expand "$p" "$x"
  [ "$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$x/Distribution" | grep -v '^default$' | head -1)" = dev.mavergreen.base ] \
    || fail "$(basename "$p"): the base component comes first"
  for comp in "$x"/*.pkg; do (cd "$V" && gzip -dc "$comp/Payload" | cpio -id --quiet); done
done
grep -q "os-version min=\"$CROSS_MIN_OS\"" "$W"/x-golang-*-cross-*.pkg/Distribution || fail "the cross archive's floor is CROSS_MIN_OS ($CROSS_MIN_OS): Go stamps the toolchain's own binaries with it"
pb() { /usr/libexec/PlistBuddy -c "Print :$2" "$V/usr/local/mavergreen/$1/mavergreen.plist"; }
[ "$(pb go$GO_LINE group)/$(pb go$GO_LINE line)" = go/$GO_LINE ] || fail "go$GO_LINE is group go, line $GO_LINE"
[ "$(pb go$GO_LINE-cross group)/$(pb go$GO_LINE-cross line)" = go/$GO_LINE-cross ] || fail "go$GO_LINE-cross is group go, line $GO_LINE-cross"
MG() { sh "$SHIPYARD_SCRIPTS/mavergreen.sh" --root "$V" "$@"; }
F="$V/usr/local/mavergreen/bin"
MG link go$GO_LINE || fail "linking the native toolchain must succeed"
MG link go$GO_LINE-cross || fail "linking the cross toolchain beside the native one must succeed"
MG check || fail "a box with both toolchains installed must pass mavergreen check"
[ "$(MG select go)" = go$GO_LINE ] || fail "the first member installed keeps the selection; installing the second never takes it"
[ "$(readlink "$F/go")" = ../go$GO_LINE/bin/go ] || fail "bare go belongs to the selected member, the native toolchain"
[ "$(readlink "$F/go-$GO_LINE")" = ../go$GO_LINE/bin/go ] || fail "go-$GO_LINE runs the native toolchain"
[ "$(readlink "$F/go-$GO_LINE-cross")" = ../go$GO_LINE-cross/bin/go ] || fail "go-$GO_LINE-cross runs the cross toolchain, selected or not"
MG select go go$GO_LINE-cross || fail "select must move the go group to the cross toolchain"
[ "$(readlink "$F/go")" = ../go$GO_LINE-cross/bin/go ] && [ "$(readlink "$F/gofmt")" = ../go$GO_LINE-cross/bin/gofmt ] \
  || fail "after select, every bare name belongs to the cross toolchain"
[ "$(readlink "$F/go-$GO_LINE")" = ../go$GO_LINE/bin/go ] || fail "select leaves the native toolchain's versioned names alone"
MG check || fail "mavergreen check must stay clean after select"
for gone in mavericks-clang mavericks-clang-$GO_LINE mavericks-cross-clang mavericks-cross-clang-$GO_LINE-cross; do
  [ ! -e "$F/$gone" ] && [ ! -L "$F/$gone" ] || fail "$gone is go.env's CC wrapper, not a user command"
done
echo "PASS: package-manifest"
