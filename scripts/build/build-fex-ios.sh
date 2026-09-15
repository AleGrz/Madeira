#!/usr/bin/env bash
set -euo pipefail
# Minimum iOS version for every native artifact in the app bundle. Overridable
# so a contributor can raise it; 16.0 is the floor the project supports.
IOS_MIN="${IOS_MIN:-16.0}"
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
SRC="$ROOT/FEX"
BUILD="$SRC/build-ios"
OUT="$BUILD/FEXCore/Source/libFEXCore.a"

if [[ -f "$OUT" ]]; then
  echo "FEX iOS: cached"
  exit 0
fi

# A configure that died leaves a CMakeCache.txt behind, and the next run reuses
# it and reproduces the same failure even after the missing tool is installed --
# "CMAKE_MAKE_PROGRAM is not set" is self-perpetuating that way. build.ninja only
# appears once configure has finished, so its absence marks the directory as
# wreckage rather than progress. Compiled objects survive whenever configure did
# complete, which is the case worth caching.
if [[ -e "$BUILD/CMakeCache.txt" && ! -f "$BUILD/build.ninja" ]]; then
  echo "Dropping incomplete CMake configure in $BUILD"
  rm -rf "$BUILD"
fi

# -DFEX_IOS_HOST=1 selects the iOS host-feature stubs inside this FEX fork
# (HostFeatures, InvalidationTracker, logging). A build without it compiles
# but misdetects the host at runtime, so it is required here, not optional.
# Hand CMake the ninja binary outright. The generator's own search is what
# reported "CMAKE_MAKE_PROGRAM is not set", and build-ipa.sh has already proven
# ninja exists by this point, so there is nothing left for that search to decide.
NINJA="$(command -v ninja || true)"
[[ -n "$NINJA" ]] || { echo "ERROR: ninja is required (brew install ninja)" >&2; exit 1; }

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS=-DFEX_IOS_HOST=1 \
  -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST=1 \
  -DBUILD_TESTING=OFF \
  -DBUILD_FEX_LINUX_TESTS=OFF \
  -DBUILD_THUNKS=OFF \
  -DBUILD_FEXCONFIG=OFF \
  -DBUILD_STEAM_SUPPORT=OFF \
  -DENABLE_LTO=OFF \
  -DENABLE_CCACHE=OFF \
  -DTUNE_CPU=generic \
  -DTUNE_ARCH=generic

cmake --build "$BUILD" --parallel "$JOBS"
[[ -f "$OUT" ]] || { echo "ERROR: FEX build did not produce $OUT" >&2; exit 1; }
