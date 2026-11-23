#!/bin/sh
# platform: host-agnostic
#   usage: sh build/build.sh [native] [cross] [linux-cross] [updaters] [packages]
#          A developer's whole build, in order, through golang-port's build chain (build/port.sh resolves the port:
#          GOLANG_PORT_DIR, or the pinned release). With no arguments: native and cross; on a Linux host also linux-cross.
#          `updaters` builds both Sparkle updaters and `packages` both .pkgs (which need the updaters).
#          Products land under $MAVERICKS_BUILD_ROOT (default ${TMPDIR:-/tmp}/mm-build): $WORK/staging, $WORK/staging-cross,
#          $WORK/out. Each step is `LINE_ROOT=<this checkout> sh "$PORT_DIR/build/<step>.sh"`, as CI runs it.
set -eu
LINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LINE_ROOT
PORT_DIR="$(sh "$LINE_ROOT/build/port.sh")"
export PORT_DIR
if [ $# -eq 0 ]; then
  set -- native cross
  [ "$(uname -s)" != Linux ] || set -- "$@" linux-cross
fi
for step in "$@"; do
  case "$step" in
    native) sh "$PORT_DIR/build/build-native.sh" ;;
    cross) sh "$PORT_DIR/build/build-cross.sh" ;;
    linux-cross) sh "$PORT_DIR/build/build-linux-cross.sh" ;;
    updaters) sh "$PORT_DIR/build/build-updater.sh" native && sh "$PORT_DIR/build/build-updater.sh" cross ;;
    packages) sh "$PORT_DIR/build/package.sh" native && sh "$PORT_DIR/build/package.sh" cross ;;
    *) echo "build.sh: unknown step '$step' (native, cross, linux-cross, updaters, packages)" >&2; exit 2 ;;
  esac
done
