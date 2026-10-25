#!/bin/sh
# platform: host-agnostic
#   usage: . tests/cross/staged-sdk.sh; use_built_sdk STAGED_CROSS_GOROOT
#          points the staged tree's SDKs at the SDK the build fetched; package-cross-pkg.sh restores the link
use_built_sdk() {
  [ -d "$1/SDKs/MacOSX10.9.sdk" ] && return 0
  _sdk="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")" || return 1
  rm -rf "$1/SDKs"; mkdir "$1/SDKs"; ln -s "$_sdk" "$1/SDKs/MacOSX10.9.sdk"
}
