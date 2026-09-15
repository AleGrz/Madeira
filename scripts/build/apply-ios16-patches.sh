#!/usr/bin/env bash
# Apply the iOS 16 compatibility patches to the submodules.
#
# These live here rather than in the forks because they are specific to
# building for an OS older than the forks target: DXMT's iOS work assumes
# iOS 18 (MetalFX, Metal 3.2 AIR), and both assumptions have to be relaxed
# before the app will even load on an iPadOS 16 device.
#
# Idempotent: a patch that is already applied is skipped, so re-running the
# build over a warm checkout is safe.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

apply_patch() {
  local submodule="$1" patch="$2" on_applied="${3:-}"
  local name
  name="$(basename "$patch")"

  if [[ ! -d "$ROOT/$submodule/.git" && ! -f "$ROOT/$submodule/.git" ]]; then
    echo "ERROR: $submodule is not checked out; run git submodule update --init" >&2
    exit 1
  fi
  if git -C "$ROOT/$submodule" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "  $name: already applied"
    return
  fi

  # Not already applied, so the paths this patch owns are either pristine or
  # hold an OLDER version of these same changes -- the warm-CI-cache case, where
  # a previous run's patch is still in the tree and the new one would stack on
  # top of it instead of replacing it. Reset them to submodule HEAD first, so
  # the result is the same tree whether the cache was cold, warm-and-current, or
  # warm-and-stale. Safe because this script is the only thing that edits these
  # paths, and no two patches here touch the same file.
  local paths
  paths="$(sed -n 's,^+++ b/,,p' "$patch")"
  if [[ -n "$paths" ]]; then
    # shellcheck disable=SC2086  # word-splitting the newline-separated list is intentional
    git -C "$ROOT/$submodule" checkout HEAD -- $paths
  fi

  if git -C "$ROOT/$submodule" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$ROOT/$submodule" apply "$patch"
    echo "  $name: applied"
    [[ -n "$on_applied" ]] && "$on_applied"
    return
  fi

  echo "ERROR: $name does not apply to $submodule." >&2
  echo "       The submodule has moved; regenerate the patch against its current HEAD." >&2
  exit 1
}

# Patched sources must not be linked against a cached build of the old ones.
# build-dxmt-ios.sh short-circuits on the combined archive alone, so drop it
# and the objects it was made from when the DXMT patch actually lands.
drop_dxmt_cache() {
  rm -f "$ROOT/app/Madeira/libdxmt_combined.a" "$ROOT/build/dxmt-ios/libdxmt_combined.a"
  rm -rf "$ROOT/build/dxmt-ios/obj"
}

# The macOS host tree may be a warm cache built from the pre-patch source, so
# drop the object and the library made from it, and the completion stamp
# build-wine.sh gates on, forcing that tree through make again.
drop_wine_host_cache() {
  rm -f "$ROOT/wine/build-macos/dlls/win32u/win32u.so" \
        "$ROOT/wine/build-macos/dlls/win32u/dibdrv/bitblt.o" \
        "$ROOT/wine/build-macos/.madeira-host-built"
}

echo "Applying submodule patches"
apply_patch research/dxmt "$ROOT/patches/dxmt-ios16-metal30-metalfx.patch" drop_dxmt_cache
# Not iOS-16-specific — dibdrv/bitblt.c calls three iOS-only externs from code
# the fork left unguarded, which breaks the macOS host build's win32u.so link.
# The host tree is only built from scratch on a cold Codemagic cache, which is
# why it surfaced there and nowhere else. Fixing it upstream in the fork would
# be neater; carrying it here keeps the submodule pin unchanged.
apply_patch wine "$ROOT/patches/wine-win32u-srcwatch-ios-guard.patch" drop_wine_host_cache
# Same shape, PE side: loader.c's ml701 IAT sweep calls xlate_ios_jit, which only
# the arm64ec build defines, so the host tree's plain-arm64 ntdll.dll fails to
# link. The host tree is configured --enable-archs=aarch64, so it is the only
# build that hits this.
apply_patch wine "$ROOT/patches/wine-ntdll-iat-life-arm64ec-only.patch" drop_wine_host_cache
