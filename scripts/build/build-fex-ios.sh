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

# -DFEX_IOS_HOST=1 selects the iOS host-feature stubs inside this FEX fork
# (HostFeatures, InvalidationTracker, logging). A build without it compiles
# but misdetects the host at runtime, so it is required here, not optional.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
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
