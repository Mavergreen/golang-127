#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/../.."
fail=0
# Directories to scan. 'test' never existed -- a grep aimed at a missing directory checks nothing
# while still looking like a guard.
scan="patches build tests"
if grep -ril pkgsrc $scan 2>/dev/null | grep -v rename-check.sh | grep -q .; then
  echo "FAIL: 'pkgsrc' still present:"; grep -ril pkgsrc $scan | grep -v rename-check.sh
  fail=1
fi
[ -f build/extract-patches.sh ] && { echo "FAIL: extract-patches.sh not removed"; fail=1; }
# spec: PORT.md, "Hook ↔ overlay interface" -- the overlay (crypto/x509's root_keychainunion* files and their testdata)
#       comes from golang-port; this repo carries only hook patches, which edit upstream files.
if grep -lE '^\+\+\+ src/crypto/x509/(root_keychainunion|testdata/keychainunion)' patches/*.patch 2>/dev/null | grep -q .; then
  echo "FAIL: these patches add overlay files, which come from golang-port (its apply-overlay.sh refuses a file that already exists):"
  grep -lE '^\+\+\+ src/crypto/x509/(root_keychainunion|testdata/keychainunion)' patches/*.patch
  fail=1
fi
[ "$fail" = 0 ] && echo "rename-check OK"
exit $fail
