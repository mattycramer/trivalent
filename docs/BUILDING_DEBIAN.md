# Building Trivalent on Debian (x86_64, local install tree)

This fork targets **Debian x86_64 only**. Trivalent is built on modern Debian
using an ungoogled-chromium source tarball as the upstream base. The helper
script below creates a local install tree (no .deb packaging) suitable for
testing on the build machine. It uses ungoogled-chromium’s `utils/` pipeline
to download and prepare Chromium sources before applying Trivalent patches.

## 1) Prerequisites

Ensure a standard Chromium build toolchain is present (clang/llvm, lld, ninja,
python3, pkg-config, and the usual X11/Wayland/GTK/VA-API dev libraries).
If you already build Chromium on Debian, you likely have everything needed.
The Dawn/WebGPU build requires X11 XCB headers (`libx11-xcb-dev`).

At minimum, the helper script requires:
- `python3`
- `ninja`
- `curl`
- `git` (or `patch`)
- `nodejs`
- `clang`, `lld`, `libclang-dev`, `rustc`, `bindgen`, and `rustfmt` (when `USE_SYSTEM_TOOLCHAIN=1`)

The build script also checks Chromium’s full Debian dependency list (from
`build/install-build-deps.py`) and will print any missing packages before it
starts compiling. Printing is disabled in this Debian build, so CUPS packages
(`libcups2-dev`/`libcups2`) are excluded. We also drop cross-toolchain and
test-runner packages (e.g., `binutils-*-linux-*`, `xvfb`, `openbox`) because this
fork targets **Debian x86_64 local builds only**.

PipeWire development headers are required because the build enables WebRTC
PipeWire support (`rtc_use_pipewire=true`).

## 2) Rootless container build (Docker Compose)

This repo includes a rootless container workflow using Docker Compose. It
builds on Debian **trixie** by default (Debian‑only) and runs the same
`debian_build.sh` script inside the container. You can override the suite if
you want newer packages (e.g., sid).

The container installs a **pinned Rust nightly (2025-11-07)** via rustup so
Chromium’s required `-Z` rustc flags work without `RUSTC_BOOTSTRAP`. The clang
toolchain must **match the LLVM version embedded in that nightly**. By default
the container installs LLVM/clang **21**. If the requested LLVM version is not
available in your Debian suite, the Dockerfile falls back to the default
`clang/lld/llvm` packages and `debian_build.sh` will stop early if the LLVM
majors do not match.

Override the toolchain if you need a different dated nightly:

```bash
RUSTUP_TOOLCHAIN=nightly-2025-11-07 make image
```

From the repo root:

```bash
make image
make build
```

The container reuses the repo’s `.cache/` directory for downloads. The
`make build` target will create it if it doesn’t exist and relax permissions
so the rootless container user can write to the bind mount.

Override toolchain versions if needed:

```bash
DEBIAN_SUITE=sid make image
```

If your Debian suite provides a different LLVM major version, set it explicitly
and ensure the Rust nightly you pin is built with the same LLVM major:

```bash
LLVM_VERSION=21 RUSTUP_TOOLCHAIN=nightly-2025-11-07 make image
```

Clean container resources and build artifacts:

```bash
make clean
```

## 3) Build with the Debian helper (host)

From the repo root:

```bash
./debian_build.sh
```

The script will:
1) Download ungoogled-chromium `144.0.7559.109-1` (or a tag you specify)
2) Use ungoogled-chromium `utils/` to download and prepare Chromium sources
3) Apply Vanadium + Trivalent patches
4) Configure GN args for a hardened, no-proprietary-codecs build
5) Build `chrome`
6) Create a local install tree in `out/debian/install`

### Debian ports of Fedora patches

The `fedora_patches/` directory is retained for reference. Debian builds apply
ported equivalents under `patches/` to keep the system toolchain and Chromium
sources compatible:

- `debian-disable-nodejs-version-check.patch` (system Node.js)
- `debian-csss-style-sheet-include.patch` (CSSStyleSheet include fix)
- `debian-rust-libadler2.patch` (Rust stdlib file selection)
- `debian-rust-bindgen-libclang-path.patch` (libclang path for Debian layouts)
- `debian-rust-bindgen-generator-libclang-path.patch` (bindgen generator libclang path)
- `debian-bytemuck-disable-nightly-portable-simd.patch` (fix bytemuck portable SIMD on nightly)
- `debian-fontconfig-bindgen-opaque-io-file.patch` (avoid bindgen bitfield warnings from glibc)
- `debian-rustfmt-unstable-features.patch` (enable nightly rustfmt unstable features to avoid warnings)
- `debian-fix-unused-ipv6-probe-warnings.patch` (avoid unused IPv6 probe warnings on clang)
- `debian-gpu-utils-re2-dep.patch` (add re2 dep for gpu_utils)
- `debian-clean-warnings.patch` (targeted warning fixes for Debian-only build)
- `debian-clean-warnings-2.patch` (additional warning fixes from disabled features)
- `debian-disable-printing-allowlist.patch` (guard printing pref allowlist when printing is disabled)

These ports keep the build aligned with Debian’s multiarch LLVM layout
(`/usr/lib/llvm-<ver>/lib`) while preserving the hardened defaults.

Fedora’s redhat-only compiler-rt libdir patch is intentionally **not** ported,
because Debian uses multiarch paths and the build scripts already supply
`clang_base_path` and multiarch libdir detection.

### GPU sandbox patch (Debian)

Debian builds now apply `patches/linux-gpu-sandbox.patch`, which enables a
Linux GPU sandbox path that is compatible with Debian’s multiarch library
layout (`/usr/lib/x86_64-linux-gnu`). It is **off by default** and can be
enabled with:

```
--enable-gpu-sandbox-linux --ozone-platform=wayland
```

For Mesa/Gallium drivers, an optional `--libgallium-version=<X.Y.Z>` can be
passed to whitelist the exact `libgallium-<X.Y.Z>.so` in the sandbox. This
input is validated for safety before use.

### Optional environment variables

- `RUSTC_BOOTSTRAP` — set to `1` automatically for Debian system toolchains to
  allow Chromium’s required nightly-only rustc flags. Override if you supply a
  nightly toolchain.
- `UGC_TAG` — ungoogled-chromium tag (default: `144.0.7559.109-1`)
- `UGC_URL` — tarball URL (default points at the GitHub tag tarball)
- `UGC_SHA256` — expected SHA-256 for the tarball (recommended)
- `USE_SYSTEM_TOOLCHAIN` — `1` to use system clang/rust (default: `1`)
- `USE_QT6` — `1` or `0` (default: auto-detect)
- `TRIVALENT_MARCH_NATIVE` — `1` to use `-march/-mtune=native` (default: `1`)
- `STRIP_BINARIES` — `1` to strip binaries in the install tree (default: `1`)
- `CLEAN_SRC` — `1` to re-extract the ungoogled repo (default: `0`)

Example:

```bash
UGC_SHA256="<fill-in-release-sha256>" TRIVALENT_MARCH_NATIVE=1 ./debian_build.sh
```

## 4) Running the build

The install tree is located at:

```
out/debian/install
```

You can run the built wrapper directly:

```bash
out/debian/install/usr/bin/trivalent
```

> Note: `-march=native` produces binaries optimized for the build machine.
> Disable `TRIVALENT_MARCH_NATIVE` if you plan to copy the install tree to
> different hardware.
