# syntax=docker/dockerfile:1.6
ARG DEBIAN_SUITE=trixie
FROM debian:${DEBIAN_SUITE}-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=builder
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG UGC_TAG=144.0.7559.109-1
ARG UGC_URL=https://github.com/ungoogled-software/ungoogled-chromium/archive/refs/tags/${UGC_TAG}.tar.gz
ARG RUSTUP_TOOLCHAIN=nightly-2025-11-07
ARG LLVM_VERSION=21

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
ENV LLVM_VERSION=${LLVM_VERSION}
ENV PATH=/opt/cargo/bin:/usr/lib/llvm-${LLVM_VERSION}/bin:$PATH

# Base tooling and repository setup
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dirmngr \
    gnupg \
    lsb-release \
    apt-transport-https; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-venv \
    python3-requests \
    ninja-build \
    pkg-config \
    file \
    xz-utils \
    bzip2 \
    zip \
    unzip \
    gperf \
    bison \
    flex \
    nodejs \
    bindgen; \
  if apt-cache show clang-${LLVM_VERSION} >/dev/null 2>&1; then \
    apt-get install -y --no-install-recommends \
      clang-${LLVM_VERSION} \
      lld-${LLVM_VERSION} \
      llvm-${LLVM_VERSION} \
      libclang-rt-${LLVM_VERSION}-dev \
      libclang-${LLVM_VERSION}-dev \
      libc++-${LLVM_VERSION}-dev \
      libc++abi-${LLVM_VERSION}-dev; \
  else \
    echo "LLVM ${LLVM_VERSION} packages not available; using default clang/lld/llvm from Debian."; \
    apt-get install -y --no-install-recommends \
      clang \
      lld \
      llvm \
      libclang-rt-dev \
      libclang-dev \
      libc++-dev \
      libc++abi-dev; \
  fi; \
  rm -rf /var/lib/apt/lists/*

# Install pinned Rust nightly via rustup for Chromium's -Z flags.
RUN set -eux; \
  curl -fL --retry 3 --retry-delay 2 -o /tmp/rustup-init.sh https://sh.rustup.rs; \
  sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain "${RUSTUP_TOOLCHAIN}"; \
  rm -f /tmp/rustup-init.sh; \
  rustup component add rustfmt --toolchain "${RUSTUP_TOOLCHAIN}"; \
  mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"; \
  chown -R root:root "$RUSTUP_HOME" "$CARGO_HOME"

# Install Chromium build dependencies (Debian-only, printing/CUPS excluded)
RUN <<EOF
set -eux
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/cache"
curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/ugc.tar.gz" "$UGC_URL"
tar -xf "$tmpdir/ugc.tar.gz" -C "$tmpdir"
ugc_repo="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'ungoogled-chromium-*' | head -n 1)"
if [ -z "$ugc_repo" ]; then
  echo "Failed to locate extracted ungoogled-chromium repo."
  exit 1
fi
python3 "$ugc_repo/utils/downloads.py" retrieve -c "$tmpdir/cache" -i "$ugc_repo/downloads.ini"
python3 "$ugc_repo/utils/downloads.py" unpack -c "$tmpdir/cache" -i "$ugc_repo/downloads.ini" -- "$tmpdir/chromium"
apt-get update
python3 - "$tmpdir/chromium/build/install-build-deps.py" <<'PY' > "$tmpdir/deps.txt"
import importlib.util
import sys
import subprocess

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("deps", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

options = mod.parse_args([])
packages = mod.package_list(options)

include = {
    "libgtk-3-dev",
    "libpipewire-0.3-dev",
    "libx11-xcb-dev",
    "libxkbcommon-dev",
    "libnss3-dev",
    "libglib2.0-dev",
    "libudev-dev",
}

exclude = {
    "libcups2-dev",
    "libcups2",
    "binutils-arm-linux-gnueabihf",
    "binutils-mipsel-linux-gnu",
    "binutils-mips64el-linux-gnuabi64",
    "binutils-aarch64-linux-gnu",
    "lib32z1",
    "dbus-x11",
    "openbox",
    "xcompmgr",
    "xserver-xorg-video-dummy",
    "xvfb",
    "rpm",
    "cdbs",
    "devscripts",
    "lighttpd",
    "git-core",
}

replace_map = {
    "libasound2": "libasound2t64",
    "libatk1.0-0": "libatk1.0-0t64",
    "libatspi2.0-0": "libatspi2.0-0t64",
    "libbrlapi0.5": "libbrlapi0.8",
    "libgtk-3-0": "libgtk-3-0t64",
    "libncurses5": "libncurses6",
    "libnspr4-0d": "libnspr4",
    "libnss3-1d": "libnss3",
    "libjpeg62-dev": "libjpeg62-turbo-dev",
    "libjpeg62": "libjpeg62-turbo",
    "libpng12-0": "libpng16-16",
}

def candidate_exists(pkg):
    try:
        result = subprocess.run(
            ["apt-cache", "policy", pkg],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except FileNotFoundError:
        return True
    for line in result.stdout.splitlines():
        if line.strip().startswith("Candidate:"):
            return "(none)" not in line
    return False

missing = []
resolved = []
for pkg in packages:
    if pkg in exclude:
        continue
    replacement = replace_map.get(pkg, pkg)
    if replacement != pkg and candidate_exists(replacement):
        resolved.append(replacement)
        continue
    if candidate_exists(pkg):
        resolved.append(pkg)
        continue
    missing.append(pkg)

packages = resolved
for pkg in include:
    if pkg in packages:
        continue
    if candidate_exists(pkg):
        packages.append(pkg)
    else:
        missing.append(pkg)

if missing:
    print("Missing packages (no candidate):", file=sys.stderr)
    for pkg in sorted(set(missing)):
        print(f"  - {pkg}", file=sys.stderr)

for pkg in sorted(set(packages)):
    print(pkg)
PY
xargs -r apt-get install -y --no-install-recommends < "$tmpdir/deps.txt"
rm -rf "$tmpdir"
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Create an unprivileged user for rootless builds
RUN set -eux; \
  groupadd -g "$GROUP_ID" "$USERNAME"; \
  useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash "$USERNAME"

RUN set -eux; \
  chown -R "$USER_ID":"$GROUP_ID" "$RUSTUP_HOME" "$CARGO_HOME"

USER ${USERNAME}
WORKDIR /workspace

ENV USE_SYSTEM_TOOLCHAIN=1
ENV TRIVALENT_MARCH_NATIVE=1
