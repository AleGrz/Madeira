#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
# Minimum iOS version for every native artifact and for the app itself. 16.0
# covers the oldest device this project targets (M1 iPad on iPadOS 16.3).
# Raise it with IOS_MIN=18.0 to build an 18-only bundle.
IOS_MIN="${IOS_MIN:-16.0}"
export ROOT JOBS IOS_MIN

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Madeira must be built on macOS with Xcode."
command -v xcodebuild >/dev/null || die "Xcode is required. Install it from the App Store first."
command -v xcrun >/dev/null || die "Xcode command-line tools are required."
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"
command -v python3 >/dev/null || die "python3 is required (ships with Xcode command-line tools)."

# A changed deployment target only reaches artifacts that are actually rebuilt,
# and every expensive one here is cached by existence. Say so loudly rather than
# shipping a bundle half-built for the old target.
STAMP="$ROOT/build/.ios-min"
PREVIOUS_MIN="unstamped"
if [[ -f "$STAMP" ]]; then PREVIOUS_MIN="$(cat "$STAMP")"; fi
if [[ "$PREVIOUS_MIN" != "$IOS_MIN" ]] &&
   [[ -d "$ROOT/FEX/build-ios" || -d "$ROOT/toolchains/llvm-ios-build" ||
      -f "$ROOT/app/Madeira/libdxmt_combined.a" ]]; then
  printf '\n\033[1;33m==> iOS deployment target changed: %s -> %s\033[0m\n' "$PREVIOUS_MIN" "$IOS_MIN"
  echo "    Cached native artifacts were built for the old target and will be reused."
  echo "    For a fully consistent bundle delete these first (they are rebuilt, slowly):"
  echo "      FEX/build-ios  toolchains/llvm-ios-build  build/dxmt-ios  build/gnutls-ios"
  echo "      build/freetype-ios  build/ntdll-unix  build/win32u-unix  build/wineserver"
fi
mkdir -p "$ROOT/build"
printf '%s' "$IOS_MIN" > "$STAMP"

log "Installing build dependencies"
# One formula per call. `brew install a b c ...` gives up on the first formula
# that errors and never reaches the rest, and `|| true` then hides that the
# whole tail of the list was skipped -- which is how a run arrived at FEX's
# cmake with no ninja installed and failed there, 20 minutes in, instead of
# here. Per-formula failures stay non-fatal (most are idempotent no-ops); the
# require_tool gate below is what actually decides whether the build can run.
for formula in cmake ninja meson pkg-config autoconf automake libtool bison flex sevenzip llvm xxd; do
  brew install "$formula" || echo "WARNING: brew install $formula failed" >&2
done

# bison, flex and llvm are keg-only: Homebrew deliberately keeps them off the
# default PATH, so each one has to be prepended by hand. `brew --prefix <keg>`
# answers with a path whether or not the formula is installed, which is how a
# silently failed install ends up pointing PATH at a directory that does not
# exist -- and then Wine's configure picks up macOS's own bison 2.3 and stops
# with "Your bison version is too old".
for keg in bison flex llvm; do
  keg_prefix="$(brew --prefix "$keg" 2>/dev/null || true)"
  if [[ -n "$keg_prefix" && -d "$keg_prefix/bin" ]]; then
    PATH="$keg_prefix/bin:$PATH"
  else
    echo "WARNING: Homebrew $keg is not installed; the system copy will be used" >&2
  fi
done
export PATH

# Every tool the build actually invokes, checked once here with PATH final. A
# missing one gets a second solo install whose error is allowed to surface, then
# a hard stop naming the tool -- cheaper than "CMake was unable to find a build
# program corresponding to Ninja" after the Wine tree has already been built.
# Only tools that are really called are listed: meson and pkg-config are
# installed above out of caution but nothing in the build path runs them.
require_tool() {
  local cmd="$1" formula="$2"
  command -v "$cmd" >/dev/null && return
  log "Installing $formula (provides $cmd)"
  brew install "$formula"
  command -v "$cmd" >/dev/null ||
    die "$cmd is required but is still not on PATH after 'brew install $formula'."
}
require_tool cmake cmake        # FEX, LLVM, DXMT, FreeType
require_tool ninja ninja        # -G Ninja generator for FEX and LLVM
require_tool bison bison        # Wine configure
require_tool flex flex          # Wine configure
require_tool xxd xxd            # shader headers, dxbc blobs
require_tool 7zz sevenzip       # vcruntime extraction

# Check it here, where the message can say which binary was picked, rather than
# inside Wine's configure an hour into the build. macOS ships bison 2.3 in
# /usr/bin and Wine wants 3.0+, so this is the one that actually bites.
bison_version="$(bison --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' | head -1 || true)"
bison_major="${bison_version%%.*}"
if ! [[ "$bison_major" =~ ^[0-9]+$ ]] || (( bison_major < 3 )); then
  echo "bison in use: $(command -v bison 2>/dev/null || echo '<none>') (version '${bison_version:-unknown}')" >&2
  die "Wine's configure needs bison 3.0 or newer. Install it with: brew install bison"
fi
log "Using bison $bison_version ($(command -v bison))"

log "Checking out submodules"
git -C "$ROOT" submodule update --init --recursive

bash "$ROOT/scripts/build/apply-ios16-patches.sh"

log "Validating bundled Wine prefix"
bash "$ROOT/tools/check-prefix-template.sh" "$ROOT/app/Madeira/prefix-template.tar.gz"

"$ROOT/scripts/build/setup-llvm-mingw.sh"
"$ROOT/scripts/build/build-wine.sh"
"$ROOT/scripts/build/build-fex-ios.sh"
"$ROOT/scripts/build/build-freetype-ios.sh"

log "Building GnuTLS stack for iOS"
"$ROOT/build/gnutls-ios/build.sh"
"$ROOT/scripts/build/sync-gnutls-libs.sh"

log "Bootstrapping wineserver"
"$ROOT/build/wineserver/bootstrap.sh"
"$ROOT/build/wineserver/build.sh"

log "Building Wine unix libraries"
"$ROOT/build/ntdll-unix/build.sh"
"$ROOT/build/win32u-unix/build.sh"

"$ROOT/scripts/build/build-llvm-ios.sh"
"$ROOT/scripts/build/build-shader-headers.sh"
"$ROOT/scripts/build/build-dxmt-ios.sh"
"$ROOT/scripts/build/prepare-vcruntime.sh"
"$ROOT/scripts/build/package-ipa.sh"

printf '\n\033[1;32mDone: %s/dist/Madeira.ipa\033[0m\n' "$ROOT"
