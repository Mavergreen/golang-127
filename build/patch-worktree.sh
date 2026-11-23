#!/bin/sh
# platform: host-agnostic
#   usage: MAVERICKS_WORK=$HOME/.cache/mavericks-golang/patchwork sh build/patch-worktree.sh
#          Prepares an editable Go tree for patch work: $WORK/go = upstream (UPSTREAM_VERSION) + this line's hook patches
#          + golang-port's overlay, and $WORK/go.pristine = the same upstream untouched, which build/mkpatch.sh diffs against.
#          Give it a WORK of its own so a build never clobbers edits.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/versions.sh"
sh "$PORT_DIR/build/fetch-go.sh"
rm -rf "$WORK/go.pristine"
mkdir -p "$WORK/go.pristine"
( cd "$WORK/go" && tar -cf - . ) | ( cd "$WORK/go.pristine" && tar -xf - )
sh "$PORT_DIR/build/apply-patches.sh"
echo "editable: $WORK/go   pristine: $WORK/go.pristine"
