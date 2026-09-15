#!/bin/bash
# Build freetype static for iOS arm64 — consumed by build/win32u-unix/build.sh,
# which compiles freetype_ios.c against these headers and merges
# build/libfreetype.a into libwin32u_unix.a (no Xcode project changes).
#
# Source: shallow clone of freetype 2.13.3 in research/freetype
#   git clone --depth 1 --branch VER-2-13-3 https://github.com/freetype/freetype.git research/freetype
# All optional deps disabled — fonts are plain TTFs from wine/fonts/.
set -e
# Minimum iOS version for every native artifact in the app bundle. Overridable
# so a contributor can raise it; 16.0 is the floor the project supports.
IOS_MIN="${IOS_MIN:-16.0}"

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
SRC="$REPO_ROOT/research/freetype"

[ -d "$SRC" ] || { echo "ERROR: clone freetype first (see header)"; exit 1; }

# A configure that died leaves a CMakeCache.txt behind, and the next run reuses
# it and reproduces the same failure even after the missing tool is installed --
# "CMAKE_MAKE_PROGRAM is not set" is self-perpetuating that way. Makefile only
# appears once configure has finished, so its absence marks the directory as
# wreckage rather than progress. Compiled objects survive whenever configure did
# complete, which is the case worth caching.
if [[ -e "$BUILD_DIR/build/CMakeCache.txt" && ! -f "$BUILD_DIR/build/Makefile" ]]; then
  echo "Dropping incomplete CMake configure in $BUILD_DIR/build"
  rm -rf "$BUILD_DIR/build"
fi

cmake -S "$SRC" -B "$BUILD_DIR/build" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON \
  -DCMAKE_C_FLAGS="-fno-stack-protector"

cmake --build "$BUILD_DIR/build" -j8
echo "Done: $BUILD_DIR/build/libfreetype.a"
