#!/bin/sh
# platform: macOS-only -- pkgutil expands the prebuilt shim's installer pkg
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
: "${MLS_VERSION:?set MLS_VERSION}"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

OUT="$WORK/legacy-support"
A="$OUT/lib/libMacportsLegacySupport.a"
CACHE="$WORK/legacy-support-dl"
tag="$MLS_VERSION"
pkg_name="macports-legacy-support-$MLS_VERSION.pkg"
base="https://github.com/Mavergreen/macports-legacy-support/releases/download/$tag"

mkdir -p "$CACHE"
pkg="$CACHE/$pkg_name"
sums="$CACHE/SHA256SUMS"

# Download the pkg once (shipyard_curl renames into place only on success, so an interrupted fetch can't poison the cache).
[ -f "$pkg" ] || shipyard_curl "$base/$pkg_name" "$pkg"

# Re-fetch SHA256SUMS and verify the pkg EVERY run — a tampered cache can't silently
# change the shipped .a (this is the integrity gate that replaces the old immutable-commit check).
shipyard_curl "$base/SHA256SUMS" "$sums"
want=$(awk -v f="$pkg_name" '$2==f {print $1}' "$sums")
[ -n "$want" ] || { echo "FATAL: $pkg_name not listed in SHA256SUMS" >&2; exit 1; }
got=$(shasum -a 256 "$pkg" | awk '{print $1}')
[ "$want" = "$got" ] || { echo "FATAL: legacy-support pkg sha mismatch: $got != $want" >&2; rm -f "$pkg"; exit 1; }

# Extract the prebuilt static lib + headers from the pkg payload (no root, no compile).
exp="$CACHE/expanded"; rm -rf "$exp"
pkgutil --expand-full "$pkg" "$exp" 1>&2
a_src=$(find "$exp" -type f -name libMacportsLegacySupport.a | head -1)
[ -n "$a_src" ] || { echo "FATAL: libMacportsLegacySupport.a not found in pkg payload" >&2; exit 1; }
usrlocal=$(dirname "$(dirname "$a_src")")     # .../Payload/usr/local

rm -rf "$OUT"; mkdir -p "$OUT/lib" "$OUT/include"
cp "$usrlocal/lib/libMacportsLegacySupport.a" "$OUT/lib/"
cp -R "$usrlocal/include/LegacySupport" "$OUT/include/"

test -f "$A" || { echo "FATAL: no static .a extracted" >&2; exit 1; }
echo "$A"
