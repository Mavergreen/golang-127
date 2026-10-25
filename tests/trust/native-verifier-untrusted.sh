#!/bin/sh
# platform: macOS-only -- builds a darwin/amd64 program with the toolchain, reads its Mach-O with nm and runs it
#   On the 10.9 box: the installed toolchain (or UNTRUSTED_GOROOT); both verifiers must reject.
#   Elsewhere:       the staged cross toolchain; Recaulk's trampoline must be linked in, and where
#                    amd64 executes, Apple's verifier must reject.
#   No toolchain to test -> exit 77 (SKIP).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

on_109=no
case "$(sw_vers -productVersion 2>/dev/null)" in 10.9|10.9.*) on_109=yes ;; esac

if [ -n "${UNTRUSTED_GOROOT:-}" ]; then
  goroot="$UNTRUSTED_GOROOT"
else
  REPO_ROOT="$(cd "$here/../.." && pwd)"; export REPO_ROOT
  . "$REPO_ROOT/build/versions.sh"
  if [ "$on_109" = yes ]; then
    goroot="$PREFIX"
  else
    goroot="$WORK/staging-cross$CROSS_PREFIX"
    export CC="${CC:-$goroot/bin/mavericks-cross-clang}"
  fi
fi
[ -x "$goroot/bin/go" ] || { echo "no toolchain at $goroot -- skipping"; exit 77; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/untrusted.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset HTTPS_PROXY HTTP_PROXY ALL_PROXY GODEBUG GO_EXTLINK_ENABLED GOOS GOARCH CGO_ENABLED
export GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOCACHE="$tmp/gocache" GOPATH="$tmp/gopath" GOFLAGS=
cp -R "$here/untrusted" "$tmp/app"
( cd "$tmp/app" && go build -o "$tmp/untrusted" . ) || { echo "FAIL: the fixture does not build"; exit 1; }

fail=0
want='REJECTED x509.UnknownAuthorityError'
if [ "$on_109" = yes ]; then
  for mode in default native; do
    if [ "$mode" = native ]; then out="$(GODEBUG=x509usefallbackroots=0 "$tmp/untrusted" 2>&1)" || true
    else out="$("$tmp/untrusted" 2>&1)" || true; fi
    if [ "$out" = "$want" ]; then echo "ok   [$mode] $out"
    else echo "FAIL [$mode]: want '$want', got: $out"; fail=1; fi
  done
else
  if nm -m "$tmp/untrusted" | grep -qE '\(__TEXT,__text\) (non-)?external _SecTrustEvaluateWithError$'; then
    echo "ok   _SecTrustEvaluateWithError is defined in the binary (Recaulk's trampoline)"
  else
    echo "FAIL: _SecTrustEvaluateWithError is not defined in the binary; Recaulk did not link"; fail=1
  fi
  rc=0; out="$(GODEBUG=x509usefallbackroots=0 "$tmp/untrusted" 2>&1)" || rc=$?
  if [ "$rc" = 126 ]; then
    echo "skip [native, Rosetta]: the amd64 binary cannot execute here: $out"
  else
    case "$out" in
      REJECTED*) echo "ok   [native, Rosetta] $out" ;;
      *) echo "FAIL [native, Rosetta]: want a line starting REJECTED, got (exit $rc): $out"; fail=1 ;;
    esac
  fi
fi
[ "$fail" = 0 ] || exit 1
echo "PASS: native-verifier-untrusted"
