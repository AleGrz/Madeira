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
  if ! git -C "$ROOT/$submodule" apply --check "$patch" >/dev/null 2>&1; then
    echo "ERROR: $name does not apply to $submodule." >&2
    echo "       The submodule has moved; regenerate the patch against its current HEAD." >&2
    exit 1
  fi
  git -C "$ROOT/$submodule" apply "$patch"
  echo "  $name: applied"
  [[ -n "$on_applied" ]] && "$on_applied"
}

# Patched sources must not be linked against a cached build of the old ones.
# build-dxmt-ios.sh short-circuits on the combined archive alone, so drop it
# and the objects it was made from when the DXMT patch actually lands.
drop_dxmt_cache() {
  rm -f "$ROOT/app/Madeira/libdxmt_combined.a" "$ROOT/build/dxmt-ios/libdxmt_combined.a"
  rm -rf "$ROOT/build/dxmt-ios/obj"
}

# Wine's macOS host tree is what the fresh Codemagic run rebuilt; drop its
# stamps so the tree re-links against the patched source.
drop_wine_host_cache() {
  rm -f "$ROOT/wine/build-macos/dlls/win32u/win32u.so" \
        "$ROOT/wine/build-macos/dlls/win32u/dibdrv/bitblt.o"
}

echo "Applying submodule patches"
apply_patch research/dxmt "$ROOT/patches/dxmt-ios16-metal30-metalfx.patch" drop_dxmt_cache
# Not iOS-16-specific — the wine fork's macOS host build calls one iOS-only
# extern without the weak attribute the two neighbouring calls already carry,
# and the host tree only gets built from scratch on a cold Codemagic cache, so
# this only surfaced there. Fixing it upstream in the fork would be neater;
# carrying it here keeps the submodule pin unchanged.
apply_patch wine "$ROOT/patches/wine-win32u-srcwatch-weak.patch" drop_wine_host_cache
