#!/bin/sh
# platform: host-agnostic
#   usage: write-cross-cc.sh DIR    writes DIR/bin/mavericks-cross-clang, the cross toolchain's CC
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
dir="${1:?usage: write-cross-cc.sh DIR}"
_wlu=""; for s in $WLU_SYMS; do _wlu="$_wlu \\
  -Wl,-U,$s"; done
mkdir -p "$dir/bin"
cat > "$dir/bin/mavericks-cross-clang" <<WRAPPER
#!/bin/sh
PREFIX="\$(cd "\$(dirname "\$0")/.." && pwd)"
SDK="\$PREFIX/SDKs/MacOSX10.9.sdk"
[ -d "\$SDK" ] || { echo "mavericks-cross-clang: run 'sudo longboat sdk install 10.9' (github.com/Mavergreen/longboat)" >&2; exit 1; }
TARGET="-arch x86_64 -isysroot \$SDK -mmacosx-version-min=$MACOS_MIN"
for a in "\$@"; do
  case "\$a" in -c|-E|-S) exec /usr/bin/clang \$TARGET "\$@" ;; esac
done
exec /usr/bin/clang \$TARGET "\$@" \\
  "\$PREFIX/lib/librecaulk.a"$_wlu
WRAPPER
chmod 755 "$dir/bin/mavericks-cross-clang"
