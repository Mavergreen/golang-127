#!/bin/sh
# platform: macOS-only -- make.bash builds the darwin/arm64 toolchain with Apple's /usr/bin/clang and the pinned SDK
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"
command -v go >/dev/null || { echo "FATAL: need a stock arm64 bootstrap go on PATH" >&2; exit 1; }
GOROOT_BOOTSTRAP=$(go env GOROOT); export GOROOT_BOOTSTRAP

# inputs (same patches as native; @SSLDIR@ -> native CA convention path)
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh"); export SDK
[ -d "$SDK" ] || { echo "FATAL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }
sh "$here/fetch-go.sh"
sh "$here/apply-patches.sh"
RECAULK_A=$(sh "$here/fetch-recaulk.sh" | tail -1)
[ -f "$RECAULK_A" ] || { echo "FATAL: Recaulk archive not fetched: '$RECAULK_A'" >&2; exit 1; }

# Build the patched Go NATIVELY for the arm64 host: no Rosetta, no legacy flags, no min-10.9 on the
# toolchain itself. The 10.9-safety applies to the apps it emits (via the cross CC wrapper below),
# not to the toolchain binaries. Explicitly clear any native-build env that might leak in.
unset GOOS GOARCH GOHOSTOS GOHOSTARCH GOROOT_FINAL \
      GO_LDFLAGS BOOT_GO_LDFLAGS GO_BOOTSTRAP_LDFLAGS CGO_LDFLAGS CGO_CFLAGS GO_EXTLINK_ENABLED
# Baked as the cross linker's default (patches 0011/0012): the darwin/amd64 apps it emits external-link
# through mavericks-cross-clang even when they have no cgo. Its own arm64 links are unaffected.
export GO_EXTLINK_ENABLED=darwin/amd64
export GOROOT_FINAL="$CROSS_PREFIX"
export GOCACHE="$WORK/.gocache-cross"
( cd "$WORK/go/src" && ./make.bash -v )

# stage into a DESTDIR tree at the cross prefix
stage="$WORK/staging-cross"
rm -rf "$stage"; mkdir -p "$stage$CROSS_PREFIX"
( cd "$WORK/go" && rm -rf pkg/obj pkg/bootstrap && pax -rw . "$stage$CROSS_PREFIX" )

mkdir -p "$stage$CROSS_PREFIX/lib"
cp "$RECAULK_A" "$stage$CROSS_PREFIX/lib/librecaulk.a"
ln -s ../sdk109/SDKs "$stage$CROSS_PREFIX/SDKs"
sh "$here/write-cross-cc.sh" "$stage$CROSS_PREFIX"

# go.env defaults: target 10.9/amd64 out of the box; the wrapper handles the link.
{
  echo "GOOS=darwin"
  echo "GOARCH=amd64"
  echo "CGO_ENABLED=1"
  echo "CC=$CROSS_PREFIX/bin/mavericks-cross-clang"
} >> "$stage$CROSS_PREFIX/go.env"

test -x "$stage$CROSS_PREFIX/bin/go" || { echo "FATAL: no bin/go staged" >&2; exit 1; }
echo "$stage$CROSS_PREFIX"
