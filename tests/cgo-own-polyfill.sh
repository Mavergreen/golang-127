#!/bin/sh
# platform: macOS-only -- builds a darwin/amd64 cgo program with the toolchain and reads its Mach-O with nm
#   On the 10.9 box: the installed toolchain (or CGO_POLYFILL_GOROOT); builds AND runs.
#   Elsewhere:       the staged cross toolchain through its staged mavericks-cross-clang.
#   No toolchain to test -> exit 77 (SKIP).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

on_109=no
case "$(sw_vers -productVersion 2>/dev/null)" in 10.9|10.9.*) on_109=yes ;; esac

if [ -n "${CGO_POLYFILL_GOROOT:-}" ]; then
  goroot="$CGO_POLYFILL_GOROOT"
else
  . "$here/../build/versions.sh"
  if [ "$on_109" = yes ]; then
    goroot="$PREFIX"
  else
    goroot="$WORK/staging-cross$CROSS_PREFIX"
    export CC="${CC:-$goroot/bin/mavericks-cross-clang}"
  fi
fi
[ -x "$goroot/bin/go" ] || { echo "no toolchain at $goroot -- skipping"; exit 77; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cgo-own-polyfill.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOCACHE="$tmp/gocache" GOPATH="$tmp/gopath" GOFLAGS=
unset GO_EXTLINK_ENABLED GOOS GOARCH
export CGO_ENABLED=1
cp -R "$here/cgo-own-polyfill" "$tmp/app"
cd "$tmp/app"

go build -o "$tmp/app.bin" . || { echo "FAIL: a cgo program that defines its own SecTrustEvaluateWithError must link"; exit 1; }
n="$(nm -m "$tmp/app.bin" | grep -cE '\(__TEXT,__text\) (non-)?external _SecTrustEvaluateWithError$' || true)"
[ "$n" = 1 ] || { echo "FAIL: _SecTrustEvaluateWithError is defined $n times, want once (the program's own)"; nm -m "$tmp/app.bin" | grep SecTrustEvaluateWithError; exit 1; }
echo "ok   _SecTrustEvaluateWithError defined once"
if [ "$on_109" = yes ]; then
  out="$("$tmp/app.bin" 2>&1)" || { echo "FAIL: does not run on 10.9: $out"; exit 1; }
  echo "ok   runs on 10.9: $out"
fi
echo "PASS: cgo-own-polyfill"
