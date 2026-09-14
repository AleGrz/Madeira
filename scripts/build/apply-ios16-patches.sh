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
  local submodule="$1" patch="$2"
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
  # Patched sources must not be linked against a cached build of the old ones.
  # build-dxmt-ios.sh short-circuits on the combined archive alone, so drop it
  # and the objects it was made from.
  rm -f "$ROOT/app/Madeira/libdxmt_combined.a" "$ROOT/build/dxmt-ios/libdxmt_combined.a"
  rm -rf "$ROOT/build/dxmt-ios/obj"
}

echo "Applying iOS 16 submodule patches"
apply_patch research/dxmt "$ROOT/patches/dxmt-ios16-metal30-metalfx.patch"
