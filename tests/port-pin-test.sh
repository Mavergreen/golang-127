#!/bin/sh
# platform: host-agnostic
#   usage: sh tests/port-pin-test.sh
#          build/port.sh against a file:// MAVERGREEN_RELEASES fixture: the pinned tarball, verified by SHA256SUMS and
#          extracted fresh; a wrong or missing sum refused; GOLANG_PORT_DIR echoed as UNPINNED, and refused for a release.
#          Skips (77) without shipyard's fetch-release-pkg.sh.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
. "$R/build/msc.sh"
[ -f "${SHIPYARD_SCRIPTS:-}/fetch-release-pkg.sh" ] || { echo "no shipyard fetch-release-pkg.sh in SHIPYARD_SCRIPTS (${SHIPYARD_SCRIPTS:-unset}) -- skipping"; exit 77; }
T="$(mktemp -d "${TMPDIR:-/tmp}/port-pin-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

pin=9.8.7
line="$T/line"
mkdir -p "$line/build" "$line/components/golang-port"
cp "$R/build/port.sh" "$R/build/msc.sh" "$line/build/"
echo "$pin" > "$line/components/golang-port/version"

mkdir -p "$T/src/golang-port-$pin/build"
echo ': port fixture' > "$T/src/golang-port-$pin/build/env.sh"
rel="$T/rel/Mavergreen/golang-port/releases/download/v$pin"
mkdir -p "$rel"
(cd "$T/src" && tar -cf - "golang-port-$pin") | gzip -n > "$rel/golang-port-$pin.tar.gz"
printf '%s  golang-port-%s.tar.gz\n' "$(sha "$rel/golang-port-$pin.tar.gz")" "$pin" > "$rel/SHA256SUMS"

run() { MAVERGREEN_RELEASES="file://$T/rel" MAVERICKS_BUILD_ROOT="$T/mbr" sh "$line/build/port.sh"; }

unset GOLANG_PORT_DIR MAVERGREEN_RELEASE
out="$(run 2>"$T/err")" \
  || { cat "$T/err"; fail "the pinned tarball with a matching SHA256SUMS was refused"; }
[ "$out" = "$T/mbr/port-$pin" ] || fail "printed '$out', want the extracted port at $T/mbr/port-$pin"
[ -f "$out/build/env.sh" ] || fail "$out has no build/env.sh: the tarball's golang-port-$pin/ top dir must become the port dir"
! grep -q UNPINNED "$T/err" || fail "the pinned port was announced as UNPINNED"

touch "$out/stale"
out="$(run 2>"$T/err")" || { cat "$T/err"; fail "a second run with the same pin was refused"; }
[ ! -e "$out/stale" ] || fail "a second run kept a file the tarball does not hold: the port must be extracted fresh"

good="$(cat "$rel/SHA256SUMS")"
printf '%s  golang-port-%s.tar.gz\n' 0000000000000000000000000000000000000000000000000000000000000000 "$pin" > "$rel/SHA256SUMS"
rc=0; run >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a tarball whose sha256 disagrees with SHA256SUMS gave exit $rc, want 1"
echo "0000  something-else.tar.gz" > "$rel/SHA256SUMS"
rc=0; run >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a tarball missing from SHA256SUMS gave exit $rc, want 1"
printf '%s\n' "$good" > "$rel/SHA256SUMS"

mkdir -p "$T/dev/build"; : > "$T/dev/build/env.sh"
out="$(GOLANG_PORT_DIR="$T/dev" run 2>"$T/err")" || { cat "$T/err"; fail "GOLANG_PORT_DIR was refused outside a release"; }
[ "$out" = "$T/dev" ] || fail "with GOLANG_PORT_DIR printed '$out', want $T/dev"
grep -q "UNPINNED port $T/dev" "$T/err" || fail "GOLANG_PORT_DIR did not say 'UNPINNED port $T/dev' on stderr: an unpinned build must say so"

rc=0; GOLANG_PORT_DIR="$T/dev" MAVERGREEN_RELEASE=yes run >/dev/null 2>"$T/err" || rc=$?
[ "$rc" = 1 ] || fail "GOLANG_PORT_DIR with MAVERGREEN_RELEASE=yes gave exit $rc, want 1: nothing ships from an unpinned port"
grep -q GOLANG_PORT_DIR "$T/err" || fail "the release refusal does not name GOLANG_PORT_DIR"
echo "PASS: port-pin"
