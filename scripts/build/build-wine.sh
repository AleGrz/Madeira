#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
WINE="$ROOT/wine"
MINGW="$ROOT/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
export PATH="$MINGW:$PATH"

[[ -x "$WINE/configure" ]] || { echo "ERROR: wine submodule is missing" >&2; exit 1; }

# Native macOS build tree. Madeira's iOS unix-side libraries consume config.h,
# generated headers, and host build outputs from here. aarch64 is the native
# PE architecture used by the tracked Wine/DXMT side.
if [[ ! -f "$WINE/build-macos/Makefile" ]]; then
  echo "Configuring Wine (macOS/aarch64)..."
  mkdir -p "$WINE/build-macos"
  (
    cd "$WINE/build-macos"
    ../configure --enable-archs=aarch64 --disable-tests
  )
fi

# Gate on a stamp written only after make returns 0, not on individual outputs:
# a run that died partway through still leaves dwrite.h and winebuild behind, and
# treating that tree as "cached" hides the failure until something downstream
# misses a generated header an hour later.
HOST_STAMP="$WINE/build-macos/.madeira-host-built"
if [[ ! -f "$HOST_STAMP" ]]; then
  echo "Building Wine host tree..."
  make -C "$WINE/build-macos" -j"$JOBS"
  touch "$HOST_STAMP"
else
  echo "Wine host tree: cached"
fi

# Madeira's ntdll iOS build currently includes generated dwrite headers from a
# directory named build-arm64ec. Configure that tree reproducibly and build only
# the generated headers required by the iOS static libraries; PE binaries are
# already versioned by Madeira and are not rebuilt during onboarding.
if [[ ! -f "$WINE/build-arm64ec/Makefile" ]]; then
  echo "Configuring Wine (ARM64EC headers)..."
  mkdir -p "$WINE/build-arm64ec"
  (
    cd "$WINE/build-arm64ec"
    ../configure --enable-archs=arm64ec --disable-tests
  )
fi

if [[ ! -f "$WINE/build-arm64ec/include/dwrite.h" || ! -f "$WINE/build-arm64ec/include/dwrite_3.h" ]]; then
  echo "Generating Wine ARM64EC headers..."
  make -C "$WINE/build-arm64ec" -j"$JOBS" include/dwrite.h include/dwrite_3.h
else
  echo "Wine ARM64EC headers: cached"
fi
