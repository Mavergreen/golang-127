#!/bin/sh
# platform: host-agnostic
# A line repo is forked to make the next line. Every value that names a line must be derived from
# UPSTREAM_VERSION, or the fork silently ships the old line's names. Only the allowlist below may
# name another Go line, each for the reason given.
#
# Allowlist additions beyond the ones the plan's task brief specified verbatim:
# - tests/line-literals-test.sh (this file): once tracked, its own allowlist regexes below
#   necessarily spell out old-line tokens (e.g. golang-126, 1.26) to match against -- excluding
#   its own source is the guard declining to flag itself, not silencing a class of hits elsewhere.
# - INGREDIENTS.md:23,26,27,30,34 (golang-126, 1.26): the "Why the bootstrap Go is capped" section
#   tells golang-126's own real incident (a mergeable Renovate PR that would have built 1.26 with a
#   1.27 compiler), marked "(golang-126, 2026-09)" -- the numbers are the story, not this repo's
#   identity, so they are not rewritten.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
U="$(tr -d '[:space:]' < UPSTREAM_VERSION)"
minor="$(printf '%s' "$U" | cut -d. -f2)"
thisid="1$minor"
# One match per output line (file:lineno:match), so a line naming both this line and another is
# still caught, and the allowlist can name exact matches rather than whole lines.
hits="$(git ls-files -z \
  | xargs -0 grep -noE '(go-?|golang-)1[0-9]{2}\b|\b1\.2[0-9]\b' 2>/dev/null \
  | grep -vE ":(go-?|golang-)$thisid\$|:1\\.$minor\$" \
  | grep -vE '^tests/line-literals-test\.sh:' \
  | grep -vE '^(patches|release-notes|vendor)/' \
  | grep -vE '^PORT\.md:' \
  | grep -vE '^tests/go-src-sha256-test\.sh:' \
  | grep -vE '^tests/(trust/[a-z]+/go\.mod|cross/sample/go\.mod|pure-go-link\.sh|trust/acceptance-onbox\.sh):[0-9]+:1\.26$' \
  | grep -vE '^(README\.md|CLAUDE\.md):[0-9]+:golang-126$' \
  | grep -vE '^(\.github/renovate\.json|INGREDIENTS\.md):[0-9]+:1\.28$' \
  | grep -vE ':[0-9]+:1\.24$' \
  | grep -vE '^INGREDIENTS\.md:(23|26|27|30|34):(golang-126|1\.26)$' \
  || true)"
[ -z "$hits" ] || { printf 'FAIL: these name a Go line other than %s -- derive them from UPSTREAM_VERSION, or allowlist them here with the reason:\n%s\n' "$U" "$hits"; exit 1; }
echo "PASS: line-literals"
