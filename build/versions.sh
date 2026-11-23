#!/bin/sh
# platform: host-agnostic
#   usage: . build/versions.sh     (sourced, from a script one level down in this repo, or with REPO_ROOT set)
#          The build's variables (GO_VERSION, GO_LINE, PKG_VERSION, PREFIX, CROSS_PREFIX, CA_DIR, CROSS_MIN_OS, WORK, ...)
#          come from golang-port's build/env.sh, which reads this line's inputs: UPSTREAM_VERSION, components/*/version,
#          line.env and VERSION. PORT_DIR, when set, names the port; otherwise build/port.sh resolves it. A release
#          (MAVERGREEN_RELEASE=yes) always resolves through build/port.sh, so an inherited PORT_DIR cannot bypass the pin.
: "${REPO_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
export REPO_ROOT
LINE_ROOT="$REPO_ROOT"; export LINE_ROOT
[ "${MAVERGREEN_RELEASE:-}" != yes ] || PORT_DIR=""
[ -n "${PORT_DIR:-}" ] || PORT_DIR="$(sh "$REPO_ROOT/build/port.sh")" || exit 1
export PORT_DIR
. "$PORT_DIR/build/env.sh"
