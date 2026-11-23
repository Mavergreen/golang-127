#!/bin/sh
# platform: host-agnostic
#   usage: PORT_DIR="$(sh build/port.sh)"
#          Prints the absolute directory of the golang-port this line builds with. With GOLANG_PORT_DIR set
#          (a dev box trying a port change), that checkout, announced as UNPINNED on stderr; refused when
#          MAVERGREEN_RELEASE=yes, because nothing ships from an unpinned port. Otherwise the pinned release
#          (components/golang-port/version): golang-port-<pin>.tar.gz from Mavergreen/golang-port's v<pin>
#          release, verified against that release's SHA256SUMS by shipyard's fetch-release-pkg.sh, extracted
#          fresh into $MAVERICKS_BUILD_ROOT/port-<pin>. Exit 1 on any refusal or failed fetch.
set -eu
LINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "port.sh: $*" >&2; exit 1; }

if [ -n "${GOLANG_PORT_DIR:-}" ]; then
  [ "${MAVERGREEN_RELEASE:-}" != yes ] \
    || die "GOLANG_PORT_DIR is set ($GOLANG_PORT_DIR) and MAVERGREEN_RELEASE=yes: a release builds only with the pinned port (components/golang-port/version) -- unset GOLANG_PORT_DIR"
  [ -f "$GOLANG_PORT_DIR/build/env.sh" ] || die "GOLANG_PORT_DIR=$GOLANG_PORT_DIR is not a golang-port checkout (no build/env.sh)"
  dir="$(cd "$GOLANG_PORT_DIR" && pwd)"
  echo "UNPINNED port $dir" >&2
  printf '%s\n' "$dir"
  exit 0
fi

pinfile="$LINE_ROOT/components/golang-port/version"
[ -f "$pinfile" ] || die "no $pinfile -- the line pins its golang-port there"
pin="$(tr -d ' \t\r\n' < "$pinfile")"
case "$pin" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "$pinfile holds '$pin', not a golang-port version x.y.z" ;;
esac
case "$pin" in *[!0-9.]*) die "$pinfile holds '$pin', not a golang-port version x.y.z" ;; esac

: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
mkdir -p "$MAVERICKS_BUILD_ROOT"
root="$(cd "$MAVERICKS_BUILD_ROOT" && pwd)"
. "$LINE_ROOT/build/msc.sh"

asset="golang-port-$pin.tar.gz"
dest="$root/port-$pin"
dl="$root/port-$pin.download"
unpack="$root/port-$pin.unpack"
rm -rf "$dest" "$dl" "$unpack"
tarball="$(sh "$SHIPYARD_SCRIPTS/fetch-release-pkg.sh" golang-port "v$pin" "$asset" "$dl")" \
  || die "could not fetch $asset from Mavergreen/golang-port v$pin (see above)"
mkdir -p "$unpack"
gzip -dc "$tarball" | (cd "$unpack" && tar -xf -) || die "could not extract $tarball"
[ -f "$unpack/golang-port-$pin/build/env.sh" ] || die "$asset has no golang-port-$pin/build/env.sh"
mv "$unpack/golang-port-$pin" "$dest"
rm -rf "$dl" "$unpack"
printf '%s\n' "$dest"
