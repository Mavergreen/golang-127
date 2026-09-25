#!/bin/sh
# platform: host-agnostic
# version.sh: derives <upstream>-mavericks.N + RELEASE decision. Upstream is read from
# UPSTREAM_VERSION (NOT hardcoded) so a Renovate bump never breaks this test.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../build/version.sh"
U="$(tr -d '[:space:]' < "$here/../UPSTREAM_VERSION")"

# auto, no existing tags -> N=1, RELEASE=yes
out="$(MAVERICKS_TAGS='' sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.1$"  || { echo "FAIL auto/new FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'            || { echo "FAIL auto/new REL: $out"; exit 1; }

# auto, existing tags -> N=max, RELEASE=no
out="$(MAVERICKS_TAGS="${U}-mavericks.1
${U}-mavericks.3
${U}-mavericks.2" sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.3$"  || { echo "FAIL auto/exist FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=no$'             || { echo "FAIL auto/exist REL: $out"; exit 1; }

# local -> N=max+1, RELEASE=yes
out="$(MAVERICKS_TAGS="${U}-mavericks.3" sh "$script" local)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.4$"  || { echo "FAIL local FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'            || { echo "FAIL local REL: $out"; exit 1; }

echo "PASS: version"

# GO_LINE is DERIVED from the upstream version, not configured. Two sources of truth for "which
# line is this" is how a repo ends up building 1.26 and stamping a go127 pkg identifier.
R="$here/.."
want_line="$(printf '%s' "$U" | sed -n 's/^\([0-9]*\)\.\([0-9]*\)\..*$/\1\2/p')"
derived="$(GO_LINE= sh "$R/build/version.sh" line)"
[ "$derived" = "$want_line" ] || { echo "FAIL: derived line '$derived', expected $want_line from UPSTREAM_VERSION $U"; exit 1; }

# A caller-supplied GO_LINE is a CHECK, not an override: pairing a GO_LINE with an UPSTREAM_VERSION
# of another line must fail loudly, not silently build the wrong line. 1 is never a real Go line.
mismatch_out="$(GO_LINE=1 sh "$R/build/version.sh" line 2>&1)" && { echo "FAIL: GO_LINE=1 sh build/version.sh line should have failed, printed: $mismatch_out"; exit 1; }
echo "PASS: GO_LINE mismatch rejected"
