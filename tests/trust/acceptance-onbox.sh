#!/bin/sh
# platform: macOS-only -- runs on the 10.9 box, verifying TLS against its keychains
# On-box trust acceptance -- run ON a 10.9 box whose System keychain trusts ISRG Root X1 (as
# ultimate-hat's does). Both verifiers against real endpoints: the default Go keychain union and
# Apple's (GODEBUG=x509usefallbackroots=0); the user trust domain via userdeny; and a program that
# calls SetFallbackRoots. Keychain Access steps that need a human are in smoke-trust.sh.
#   usage: GOROOT=/path/to/goroot sh tests/trust/acceptance-onbox.sh   (e.g. /usr/local/mavergreen/go127)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
goroot="${GOROOT:?set GOROOT to the installed toolchain to test, e.g. /usr/local/mavergreen/go127}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/accept.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset HTTPS_PROXY HTTP_PROXY ALL_PROXY GODEBUG
export GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOCACHE="$tmp/gocache" GOPATH="$tmp/gopath" GOFLAGS=
mkdir -p "$tmp/vt" && cp "$here/verify_tls.go" "$tmp/vt/" && printf 'module vt\n\ngo 1.26\n' > "$tmp/vt/go.mod"
( cd "$tmp/vt" && go build -o "$tmp/verify_tls" . )
( cd "$here/userdeny" && go build -o "$tmp/userdeny" . )
( cd "$here/setfallback" && go build -o "$tmp/setfallback" . )
( cd "$here/capture" && go build -o "$tmp/capture" . )

fail=0
expect() { # mode(union|native) url want(VERIFIED|REJECTED) [substring]
  mode="$1" url="$2" want="$3" sub="${4:-}"
  if [ "$mode" = native ]; then out="$(GODEBUG=x509usefallbackroots=0 "$tmp/verify_tls" "$url" 2>&1)" || true
  else out="$("$tmp/verify_tls" "$url" 2>&1)" || true; fi
  case "$out" in
    "$want"*"$sub"*) echo "ok   [$mode] $url: $out" ;;
    *) echo "FAIL [$mode] $url: want $want${sub:+ containing '$sub'}, got: $out"; fail=1 ;;
  esac
}
for mode in union native; do
  expect "$mode" https://valid-isrgrootx1.letsencrypt.org/ VERIFIED
  expect "$mode" https://valid-isrgrootx2.letsencrypt.org/ VERIFIED
  expect "$mode" https://expired.badssl.com/ REJECTED "expired"
  expect "$mode" https://wrong.host.badssl.com/ REJECTED "is valid for"
  expect "$mode" https://untrusted-root.badssl.com/ REJECTED "unknown authority"
done
# The documented difference between the two: Apple fetches a missing intermediate, Go does not.
expect union https://incomplete-chain.badssl.com/ REJECTED "unknown authority"
expect native https://incomplete-chain.badssl.com/ VERIFIED

# SSL_CERT_FILE is honoured while the keychain is kept (smoke-trust.sh's semi-manual step 4,
# automated): capture untrusted-root.badssl.com's own root (as smoke-trust.sh's capture program
# does) and union it with the toolchain's own bundle. verify_tls's go.mod says go 1.26, so this is
# exactly the x509sslcertoverrideplatform=0-by-default case (invariant 4) -- the union must still
# honour SSL_CERT_FILE.
badssl_root="$tmp/badssl-root.pem"
"$tmp/capture" untrusted-root.badssl.com | awk '/BEGIN/{n++} n==2' > "$badssl_root"
if [ -s "$badssl_root" ]; then
  cat "$goroot/etc/openssl/certs/ca-certificates.crt" >> "$badssl_root"
  expect_env() { # url want [substring]
    url="$1" want="$2" sub="${3:-}"
    out="$(SSL_CERT_FILE="$badssl_root" "$tmp/verify_tls" "$url" 2>&1)" || true
    case "$out" in
      "$want"*"$sub"*) echo "ok   [union env] $url: $out" ;;
      *) echo "FAIL [union env] $url: want $want${sub:+ containing '$sub'}, got: $out"; fail=1 ;;
    esac
  }
  expect_env https://untrusted-root.badssl.com/ VERIFIED
else
  echo "FAIL [union env] could not capture untrusted-root.badssl.com's root"; fail=1
fi

for mode in union native; do
  rc=0
  if [ "$mode" = native ]; then GODEBUG=x509usefallbackroots=0 USERDENY_DENY_ONLY=1 "$tmp/userdeny" || rc=$?
  else "$tmp/userdeny" || rc=$?; fi
  case "$rc" in
    0) ;;
    77) echo "skip [$mode] userdeny: this account has no user-domain trust settings" ;;
    *) echo "FAIL [$mode] userdeny"; fail=1 ;;
  esac
done

if out="$("$tmp/setfallback" 2>&1)"; then echo "ok   [union] SetFallbackRoots program: $out"
else echo "FAIL [union] SetFallbackRoots program: $out"; fail=1; fi
exit "$fail"
