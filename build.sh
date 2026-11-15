#!/usr/bin/env bash
# Builds every plugin in scripting/*.sp into build/*.smx.
#
# The SourcePawn 1.12 compiler and the SourceMod include files are not part of
# the repository. Put them into tools/ (see "Building" in README.md):
#   tools/spcomp                        Linux
#   tools/spcomp64.exe or spcomp.exe    Windows (Git Bash / MSYS2)
#   tools/include/                      SourceMod include files
#
# Usage:  ./build.sh              build everything
#         ./build.sh nadethrow    build one plugin
#
# The compiler is picked by OS; override it with SPCOMP=/path/to/spcomp.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"

if [ -z "${SPCOMP:-}" ]; then
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            if [ -f "$ROOT/tools/spcomp64.exe" ]; then
                SPCOMP="$ROOT/tools/spcomp64.exe"
            else
                SPCOMP="$ROOT/tools/spcomp.exe"
            fi
            ;;
        *)
            SPCOMP="$ROOT/tools/spcomp"
            ;;
    esac
fi
if [ ! -f "$SPCOMP" ]; then
    echo "!! compiler not found: $SPCOMP" >&2
    echo "   Copy it from a SourceMod 1.12 package, see \"Building\" in README.md." >&2
    exit 2
fi
if [ ! -f "$ROOT/tools/include/sourcemod.inc" ]; then
    echo "!! SourceMod include files not found: $ROOT/tools/include" >&2
    echo "   Copy them from a SourceMod 1.12 package, see \"Building\" in README.md." >&2
    exit 2
fi
# Absolute path: we cd into scripting/ below.
SPCOMP="$(cd "$(dirname "$SPCOMP")" && pwd)/$(basename "$SPCOMP")"

mkdir -p "$OUT"

if [ $# -gt 0 ]; then
    plugins=("$@")
else
    plugins=()
    for f in "$ROOT"/scripting/*.sp; do plugins+=("$(basename "$f" .sp)"); done
fi

fail=0
cd "$ROOT/scripting"
for p in "${plugins[@]}"; do
    echo "== $p"
    rm -f "$OUT/$p.smx"
    # Paths are relative to scripting/: the Windows compiler does not understand
    # MSYS paths like /d/...; tr strips \r from its output.
    "$SPCOMP" -i../tools/include -iinclude "$p.sp" -o"../build/$p.smx" 2>&1 \
        | tr -d '\r' \
        | grep -v '^SourcePawn Compiler\|^Copyright (c)\|^$'
    if [ ! -f "$OUT/$p.smx" ]; then
        echo "!! $p: FAILED"
        fail=1
    fi
done
exit $fail
