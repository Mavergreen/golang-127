#!/bin/sh
# platform: host-agnostic
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
why="the cross toolchain ships no SDK fetcher, because Longboat's sdk109 holds the SDK (sudo longboat sdk install 10.9)"
for f in build/build-cross.sh build/package-cross-pkg.sh build/write-cross-cc.sh; do
  if grep -n 'libexec' "$R/$f"; then echo "FAIL: $f stages something into libexec/; $why"; exit 1; fi
done
for s in fetch_sdk.sh sdk-pins.sh mavericks_fetch.sh; do
  if grep -n "$s" "$R/build/write-cross-cc.sh"; then echo "FAIL: the generated mavericks-cross-clang names $s; $why"; exit 1; fi
done
echo "PASS: no-sdk-fetcher"
