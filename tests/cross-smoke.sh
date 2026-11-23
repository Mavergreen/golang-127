#!/bin/sh
# platform: host-agnostic -- builds darwin/amd64 programs and reads them; it never runs one
#   usage: sh tests/cross-smoke.sh <cross GOROOT> <clang22 bin dir>
#          The smoke release.yml runs on an installed go<line>-cross: the Linux archive extracted at its prefix (build job),
#          and the cross pkg on Apple Silicon (modern-smoke). With the toolchain's own go.env (GOOS=darwin GOARCH=amd64, its
#          CC wrapper), a cgo hello and a pure-Go hello (CGO_ENABLED=0) must build, each stamped minos 10.9 and with
#          _clock_gettime defined (Recaulk linked in), read with the given clang22's llvm-otool and llvm-nm. No arguments
#          (run-repo-tests runs every test bare): nothing installed to smoke, exit 77.
set -eu
[ $# -gt 0 ] || { echo "no cross toolchain given (release.yml passes one) -- skipping"; exit 77; }
[ $# -eq 2 ] || { echo "usage: sh tests/cross-smoke.sh <cross GOROOT> <clang22 bin dir>" >&2; exit 2; }
G="$1"; CL="$2"
fail() { echo "FAIL: cross-smoke: $*"; exit 1; }
[ -x "$G/bin/go" ] || fail "no go at $G/bin/go"
for t in llvm-otool llvm-nm; do [ -x "$CL/$t" ] || fail "no $CL/$t"; done
R="$(cd "$(dirname "$0")/.." && pwd)"
gomod="go $(tr -d '[:space:]' < "$R/UPSTREAM_VERSION" | cut -d. -f1,2)"
T="$(mktemp -d "${TMPDIR:-/tmp}/cross-smoke.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir "$T/cgo" "$T/pure"
cat > "$T/cgo/main.go" <<'GOEOF'
package main

/*
#include <unistd.h>
static long my_pid(void) { return (long)getpid(); }
*/
import "C"

import "fmt"

func main() { fmt.Println("cgo ok", int64(C.my_pid())) }
GOEOF
cat > "$T/pure/main.go" <<'GOEOF'
package main

import (
	"fmt"
	"time"
)

func main() { fmt.Println("pure-go ok", time.Now().Year() > 2000) }
GOEOF
printf 'module hellocgo\n\n%s\n' "$gomod" > "$T/cgo/go.mod"
printf 'module purego\n\n%s\n' "$gomod" > "$T/pure/go.mod"

# spec: tests/cross-smoke.sh header -- the toolchain's own go.env is under test, so nothing in the caller's environment may steer the build
unset GOOS GOARCH CGO_ENABLED CC CXX GOFLAGS GO_EXTLINK_ENABLED MAVERGREEN_CLANG22
export GOROOT="$G" GOCACHE="$T/gocache" GOPATH="$T/gopath" GOENV=off GOTOOLCHAIN=local GOPROXY=off
( cd "$T/cgo" && "$G/bin/go" build -o "$T/hello-cgo" . ) || fail "the cgo hello does not build"
( cd "$T/pure" && CGO_ENABLED=0 "$G/bin/go" build -o "$T/hello-pure" . ) || fail "the pure-Go hello does not build"

for b in hello-cgo hello-pure; do
  "$CL/llvm-otool" -hv "$T/$b" | grep -q X86_64 || fail "$b is not an x86_64 Mach-O"
  minos="$("$CL/llvm-otool" -l "$T/$b" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/ version /{print $2; exit}')"
  [ "$minos" = 10.9 ] || fail "$b: LC_VERSION_MIN_MACOSX is '${minos:-none}', want 10.9"
  "$CL/llvm-nm" --defined-only "$T/$b" | grep -q ' _clock_gettime$' || fail "$b: _clock_gettime is not defined (no Recaulk?)"
  echo "ok   $b: darwin/amd64, minos 10.9, _clock_gettime defined"
done
echo "PASS: cross-smoke"
