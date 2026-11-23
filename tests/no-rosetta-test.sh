#!/bin/sh
# platform: host-agnostic
#   usage: sh tests/no-rosetta-test.sh
#          No workflow here installs or uses Rosetta: the family's rule is no Rosetta, CI included, and x86_64 runs only on
#          10.9 (the on-target guest). golang-port's tests/rosetta-free-guard.sh reads only the port's own release.yml, so
#          this line checks its own workflows. Matches code only: comments are stripped first, so one describing the
#          antipattern is fine.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
found=0
for f in "$R"/.github/workflows/*.yml "$R"/.github/workflows/*.yaml; do
  [ -f "$f" ] || continue
  found=1
  hits="$(sed 's/#.*//' "$f" | grep -nE 'install-rosetta|/usr/libexec/rosetta|oahd|arch[[:space:]]+-(-?)(arch[[:space:]]+)?x86_64' || true)"
  [ -z "$hits" ] || { echo "FAIL: ${f#"$R"/} installs or uses Rosetta:"; printf '%s\n' "$hits" | sed 's/^/  /'; fail=1; }
done
[ "$found" = 1 ] || { echo "FAIL: no workflows under $R/.github/workflows, so nothing was checked"; exit 1; }
[ "$fail" = 0 ] || exit 1
echo "PASS: no-rosetta"
