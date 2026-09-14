# Building Madeira

Madeira is intended to be buildable from a clean clone with one command.

## Prerequisites

- macOS with a current Xcode installation and the iOS SDK
- Xcode command-line tools selected with `xcode-select`
- Homebrew
- Git

The build script installs the remaining Homebrew packages, initializes all
submodules (including DXMT's nested header submodules), downloads the pinned compiler toolchains, builds the native iOS
libraries, downloads the official Microsoft Visual C++ x64 Redistributable,
extracts the required runtime DLLs locally, builds the Xcode project, and
packages the result. Microsoft runtime DLLs are never added to Git.

Expect the first run to take several hours on a typical Mac: LLVM 15 is
compiled twice (macOS host tools, then the iOS target libraries), and FEX is
a large C++ codebase. Later runs reuse cached outputs and finish in minutes.

## Build an IPA

```sh
git clone --recurse-submodules https://github.com/willfaust/Madeira.git
cd Madeira
./scripts/build-ipa.sh
```

The output is:

```text
dist/Madeira.ipa
```

The IPA is ad-hoc signed with Madeira's requested entitlements so that a
sideloading tool such as SideStore can re-sign it with the contributor's own
development identity.

Everything is built for iOS 16.0 by default — the app, every native library,
and the DXMT pieces alike. Override it for the whole build with:

```sh
IOS_MIN=18.0 ./scripts/build-ipa.sh
```

Building for 16.0 needs two source changes that live in
`patches/dxmt-ios16-metal30-metalfx.patch` and are applied to the `research/dxmt`
submodule automatically: MetalFX is gated behind an iOS 18 availability check
(the framework does not exist before 18, and is weak-linked in the Xcode
project), and generated AIR declares the Metal version the running OS actually
has (3.0 on iOS 16, 3.1 on 17, 3.2 on 18+) instead of deriving it from the OS
major number as if it were macOS.

Note that the deployment target only reaches artifacts that are actually
rebuilt, and the expensive ones are cached by existence. After changing
`IOS_MIN` the build prints the list of directories to delete for a fully
consistent bundle.

## Re-running the build

Toolchains and expensive native build outputs are cached under their existing
ignored build directories. Re-running `./scripts/build-ipa.sh` reuses them when
they are already present. Delete an individual ignored build directory to force
that component to rebuild.

You can override parallelism with, for example:

```sh
JOBS=4 ./scripts/build-ipa.sh
```

If you already have an official `vc_redist.x64.exe`, avoid the download with:

```sh
VC_REDIST_X64="$HOME/Downloads/vc_redist.x64.exe" ./scripts/build-ipa.sh
```
