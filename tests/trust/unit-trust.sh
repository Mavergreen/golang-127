#!/bin/sh
# platform: macOS-only -- builds the patched toolchain for the host and runs crypto/x509's darwin keychain tests
# Build this line's patched Go for the HOST and run the keychain-union trust unit tests.
# The trust logic (buildKeychainUnionPool, the veto, and the env resolver) is
# build-tag-free, so a host build on macOS exercises it. This is the automated gate
# the trust patches previously lacked. Needs a Go >=1.24 bootstrap.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# Isolated work dir so this never collides with build-native's $WORK/go.
export MAVERICKS_WORK="${MAVERICKS_WORK:-$HOME/.cache/mavericks-golang/work}/trusttest"
# versions.sh defaults REPO_ROOT from dirname($0), assuming a one-level-deep
# sourcer (build/*.sh). `.` (source) never rebinds $0, and this script lives
# two levels down (test/trust/), so that default would land in test/, not the
# repo root. Set it explicitly from $here instead.
export REPO_ROOT="$(cd "$here/../.." && pwd)"
. "$here/../../build/versions.sh"
: "${GOROOT_BOOTSTRAP:=$( (command -v go >/dev/null 2>&1 && go env GOROOT) || true )}"
[ -n "${GOROOT_BOOTSTRAP:-}" ] && [ -d "$GOROOT_BOOTSTRAP" ] \
  || { echo "FATAL: set GOROOT_BOOTSTRAP to a Go >=1.24 GOROOT" >&2; exit 1; }

rm -rf "$WORK/go"
sh "$here/../../build/fetch-go.sh"
sh "$here/../../build/apply-patches.sh"
( cd "$WORK/go/src" && GOROOT_BOOTSTRAP="$GOROOT_BOOTSTRAP" ./make.bash ) 1>&2
out=$(GOROOT="$WORK/go" "$WORK/go/bin/go" test crypto/x509 -run 'KeychainUnion|Fallback|TestEnvVars|ColonSeparatedDirs|SSLCertEnvOverride|TestIssue51759|TestHybridPool' -count=1 -v 2>&1)
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^ok[[:space:]]' || { echo "FATAL: crypto/x509 trust tests did not pass" >&2; exit 1; }
# On CI a skipped trust test is a failure: the Apple-verifier tests skip only when the host's
# keychain doesn't trust the fixture, and CI's macOS does, so a skip there hides a broken path.
# Subtests print indented, so match any leading space.
if [ -n "${CI:-}" ]; then
  skipped=$(printf '%s\n' "$out" | grep -E '^[[:space:]]*--- SKIP: Test[A-Za-z_]*KeychainUnion' || true)
  [ -z "$skipped" ] || { printf 'FATAL: KeychainUnion tests skipped on CI (they must run):\n%s\n' "$skipped" >&2; exit 1; }
fi
passed=$(printf '%s\n' "$out" | grep -c '^--- PASS: Test[A-Za-z_]*KeychainUnion')
# Top-level tests only; all run on CI (the skip guard above).
[ "$passed" -ge 25 ] || { echo "FATAL: expected >=25 KeychainUnion tests to run+pass, saw $passed -- did -run match nothing?" >&2; exit 1; }
for t in TestFallback TestFallbackPanic; do
  printf '%s\n' "$out" | grep -q "^--- PASS: $t " || { echo "FATAL: upstream $t did not pass" >&2; exit 1; }
done
# CI's macOS can't exercise the 10.9 fix in systemVerify, so assert it in the source: the SSL
# policy goes to SecTrustCreateWithCertificates directly, because on OS X 10.9 SecTrustEvaluate
# faults when the policies argument is a CFArray (one built by CFArrayCreateMutable).
grep -q 'SecTrustCreateWithCertificates(certs, sslPolicy)' "$WORK/go/src/crypto/x509/root_darwin.go" \
  || { echo "FATAL: root_darwin.go no longer passes the SSL policy directly to SecTrustCreateWithCertificates -- 10.9's SecTrustEvaluate faults on a policies CFArray" >&2; exit 1; }
printf '%s\n' "$out" | grep -q '^--- PASS: TestSSLCertEnvOverride ' \
  || { echo "FATAL: TestSSLCertEnvOverride did not pass -- on darwin it pins that x509sslcertoverrideplatform has no effect" >&2; exit 1; }
for t in TestEnvVars TestLoadSystemCertsLoadColonSeparatedDirs TestIssue51759 TestHybridPool; do
  printf '%s\n' "$out" | grep -q "^--- SKIP: $t " \
    || { echo "FATAL: upstream $t did not SKIP on darwin -- patch 0018 is missing, or it asserts upstream's darwin semantics (env-exclusive roots, or Apple's verifier as the default), which go127 deliberately does not have" >&2; exit 1; }
done
grep -q 'keychainUnionPlatformRoots(); handled' "$WORK/go/src/crypto/x509/root.go" \
  || { echo "FATAL: root.go's loadSystemRoots no longer hands darwin to the keychain union (patch 0016)" >&2; exit 1; }
for os in linux windows; do
  GOROOT="$WORK/go" GOOS=$os GOARCH=amd64 "$WORK/go/bin/go" build crypto/x509 \
    || { echo "FATAL: crypto/x509 does not build for GOOS=$os -- the !darwin keychainUnionPlatformRoots stub (patch 0017) is missing" >&2; exit 1; }
done
echo "unit-trust OK ($passed trust tests passed)"
