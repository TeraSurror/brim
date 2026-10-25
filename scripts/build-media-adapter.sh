#!/bin/bash
# Builds the MediaRemote helper that Brim bundles to read Now Playing data on macOS 15.4+.
#
# macOS refuses MediaRemote access to normal apps, but /usr/bin/perl is a trusted Apple binary. The adapter
# loads MediaRemote inside perl and prints JSON; Brim only ever runs it as a helper process through this
# script's output. See docs/PROGRESS.md (M2) for why this is a dependency and what happens if it breaks.
#
# The checkout and build products live in .build/ (git-ignored). Nothing is committed except this script and
# the upstream BSD-3 license that is copied into the app bundle.
#
# Usage: ./scripts/build-media-adapter.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."

ADAPTER_REPO="https://github.com/ungive/mediaremote-adapter.git"
# Pinned so a rebuild is reproducible. Bump deliberately after testing on the current macOS.
ADAPTER_TAG="v0.7.7"
ADAPTER_SHA="e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6"

ROOT="$(pwd)"
SRC="$ROOT/.build/media-adapter-src"
OUT="$ROOT/.build/media-adapter"
FORCE="${1:-}"

if [ -d "$OUT/MediaRemoteAdapter.framework" ] && [ "$FORCE" != "--force" ]; then
    echo "MediaRemote adapter already built at $OUT (use --force to rebuild)"
    exit 0
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "error: CMake is required to build the MediaRemote adapter." >&2
    echo "       Install it with 'brew install cmake' or skip media by building with BRIM_SKIP_MEDIA_ADAPTER=1." >&2
    exit 1
fi

if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    git clone --branch "$ADAPTER_TAG" "$ADAPTER_REPO" "$SRC"
fi

ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$ADAPTER_SHA" ]; then
    echo "error: $SRC is at $ACTUAL_SHA, expected the pinned $ADAPTER_SHA." >&2
    echo "       Remove $SRC and run this script again." >&2
    exit 1
fi

cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/build" -j"$(sysctl -n hw.logicalcpu)"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$SRC/build/MediaRemoteAdapter.framework" "$OUT/"
cp "$SRC/build/MediaRemoteAdapterTestClient" "$OUT/"
cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/"
cp "$SRC/LICENSE" "$OUT/LICENSE"

echo "Built MediaRemote adapter at $OUT"
