#!/usr/bin/env bash
# Debian x86_64 local build helper for Trivalent (ungoogled-chromium base)

set -euo pipefail
IFS=$'\n\t'

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this script as root."
  exit 1
fi

if [ -r /etc/os-release ]; then
  # shellcheck source=/etc/os-release
  . /etc/os-release
  if [ "${ID:-}" != "debian" ] && ! echo "${ID_LIKE:-}" | grep -qi debian; then
    echo "This build script is Debian-only."
    exit 1
  fi
fi

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT

readonly UGC_TAG="${UGC_TAG:-144.0.7559.109-1}"
readonly UGC_URL="${UGC_URL:-https://github.com/ungoogled-software/ungoogled-chromium/archive/refs/tags/${UGC_TAG}.tar.gz}"

readonly CACHE_DIR="${CACHE_DIR:-$REPO_ROOT/.cache}"
readonly TARBALL="${TARBALL:-$CACHE_DIR/ungoogled-chromium-${UGC_TAG}.tar.gz}"
readonly WORKDIR="${WORKDIR:-$REPO_ROOT/out/debian}"
readonly SRC_DIR="${SRC_DIR:-$WORKDIR/ungoogled-src}"
readonly INSTALL_DIR="${INSTALL_DIR:-$WORKDIR/install}"
readonly UGC_BUILD_DIR="${UGC_BUILD_DIR:-$WORKDIR/uc_build}"
USE_SYSTEM_TOOLCHAIN="${USE_SYSTEM_TOOLCHAIN:-1}"
CLEAN_SRC="${CLEAN_SRC:-0}"

SKIP_PATCHES=(
  "0009-enable-fwrapv-in-Clang-for-non-UBSan-builds.patch"
  "0010-enable-ftrivial-auto-var-init-zero.patch"
  "0034-disable-browser-sign-in-feature-by-default.patch"
  "0035-disable-safe-browsing-reporting-opt-in-by-default.patch"
  "0036-disable-unused-safe-browsing-option-by-default.patch"
  "0044-disable-GaiaAuthFetcher-code-due-to-upstream-bug.patch"
  "0057-disable-appending-variations-header.patch"
  "0119-Use-local-list-of-supported-languages-for-Language-s.patch"
  "0198-Further-disable-password-leak-detection-checks.patch"
  "0200-enable-certificate-transparency-feature-by-default-f.patch"
  "trivalent-faq-page.patch"
)

mkdir -p "$CACHE_DIR" "$WORKDIR"

if [ ! -f "$TARBALL" ]; then
  echo "Downloading ungoogled-chromium ${UGC_TAG}..."
  curl -fL --retry 3 --retry-delay 2 --output "$TARBALL" "$UGC_URL"
fi

if [ -n "${UGC_SHA256:-}" ]; then
  echo "${UGC_SHA256}  ${TARBALL}" | sha256sum -c -
else
  sha256sum "$TARBALL" > "${TARBALL}.sha256"
fi

if [ "$CLEAN_SRC" = "1" ]; then
  rm -rf "$SRC_DIR"
fi
mkdir -p "$SRC_DIR"
if ! find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
  tar -xf "$TARBALL" -C "$SRC_DIR"
fi

UGC_REPO="$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$UGC_REPO" ]; then
  echo "Failed to locate extracted ungoogled-chromium repository."
  exit 1
fi

missing=()

LLVM_BIN_DIR=""
RUSTC_VERBOSE=""
RUSTC_LLVM_VERSION=""
RUSTC_LLVM_MAJOR=""
if [ "${USE_SYSTEM_TOOLCHAIN}" = "1" ] && command -v rustc >/dev/null 2>&1; then
  RUSTC_VERBOSE="$(rustc -vV 2>/dev/null || true)"
  if [ -n "$RUSTC_VERBOSE" ]; then
    RUSTC_LLVM_VERSION="$(printf '%s\n' "$RUSTC_VERBOSE" | sed -n 's/^LLVM version: //p')"
    if [ -n "$RUSTC_LLVM_VERSION" ]; then
      RUSTC_LLVM_MAJOR="${RUSTC_LLVM_VERSION%%.*}"
    fi
  fi
  if [ -n "$RUSTC_LLVM_MAJOR" ] && [ -d "/usr/lib/llvm-${RUSTC_LLVM_MAJOR}/bin" ]; then
    LLVM_BIN_DIR="/usr/lib/llvm-${RUSTC_LLVM_MAJOR}/bin"
    PATH="${LLVM_BIN_DIR}:${PATH}"
    export PATH
  fi
fi

require_cmd() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$pkg")
    return 0
  fi
  return 0
}

require_one_of() {
  local label="$1"
  shift
  local found="0"
  local cmd
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      found="1"
      break
    fi
  done
  if [ "$found" = "0" ]; then
    missing+=("$label")
    return 0
  fi
  return 0
}

require_cmd python3 "python3"
require_cmd ninja "ninja"
require_cmd node "nodejs"
require_cmd curl "curl"
require_cmd pkg-config "pkgconf"
require_cmd apt-cache "apt"
require_cmd dpkg-query "dpkg"
require_cmd file "file"
require_one_of "git (or patch)" git patch

  if [ "${USE_SYSTEM_TOOLCHAIN}" = "1" ]; then
    require_cmd clang "clang"
    require_cmd ld.lld "lld"
    require_cmd rustc "rustc"
    require_cmd bindgen "bindgen"
    require_cmd rustfmt "rustfmt"
  fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required tools:"
  printf '  - %s\n' "${missing[@]}"
  exit 1
fi

CLANG_BASE_PATH=""
CLANG_VERSION=""
RUST_SYSROOT=""
RUST_BINDGEN_ROOT=""
RUSTC_VERSION=""

if [ "${USE_SYSTEM_TOOLCHAIN}" = "1" ]; then
  if [ -z "$RUSTC_VERBOSE" ]; then
    RUSTC_VERBOSE="$(rustc -vV 2>/dev/null || true)"
  fi
  if [ -z "$RUSTC_LLVM_VERSION" ] && [ -n "$RUSTC_VERBOSE" ]; then
    RUSTC_LLVM_VERSION="$(printf '%s\n' "$RUSTC_VERBOSE" | sed -n 's/^LLVM version: //p')"
  fi
  if [ -z "$RUSTC_LLVM_MAJOR" ] && [ -n "$RUSTC_LLVM_VERSION" ]; then
    RUSTC_LLVM_MAJOR="${RUSTC_LLVM_VERSION%%.*}"
  fi

  CLANG_CANDIDATE=""
  if [ -n "$RUSTC_LLVM_MAJOR" ] && [ -x "/usr/lib/llvm-${RUSTC_LLVM_MAJOR}/bin/clang" ]; then
    CLANG_CANDIDATE="/usr/lib/llvm-${RUSTC_LLVM_MAJOR}/bin/clang"
  fi
  if [ -z "$CLANG_CANDIDATE" ]; then
    CLANG_CANDIDATE="$(command -v clang)"
  fi
  if [ -z "$CLANG_CANDIDATE" ]; then
    echo "Unable to locate clang."
    exit 1
  fi

  CLANG_REAL="$(readlink -f "$CLANG_CANDIDATE")"
  CLANG_BIN_DIR="$(dirname "$CLANG_REAL")"
  CLANG_BASE_PATH="${CLANG_BIN_DIR%/bin}"
  CLANG_VERSION="$("$CLANG_REAL" --version | head -n1 | sed -E 's/.*clang version ([0-9]+).*/\1/')"
  if [ -z "$CLANG_VERSION" ]; then
    echo "Unable to parse clang version."
    exit 1
  fi
  if [ -n "$RUSTC_LLVM_MAJOR" ] && [ "$CLANG_VERSION" != "$RUSTC_LLVM_MAJOR" ]; then
    echo "Rustc LLVM ${RUSTC_LLVM_VERSION} does not match clang ${CLANG_VERSION}."
    echo "Install clang-${RUSTC_LLVM_MAJOR}/lld-${RUSTC_LLVM_MAJOR} or use a rustc toolchain built with LLVM ${CLANG_VERSION}."
    exit 1
  fi
  CLANG_RESOURCE_DIR="$("$CLANG_REAL" --print-resource-dir)"
  BUILTINS_PRIMARY="${CLANG_RESOURCE_DIR}/lib/x86_64-unknown-linux-gnu/libclang_rt.builtins.a"
  BUILTINS_FALLBACK="${CLANG_RESOURCE_DIR}/lib/linux/libclang_rt.builtins-x86_64.a"
  if [ -f "$BUILTINS_PRIMARY" ]; then
    :
  elif [ -f "$BUILTINS_FALLBACK" ]; then
    echo "Using clang builtins from ${BUILTINS_FALLBACK} (Debian layout)."
  else
    echo "Missing clang runtime builtins in ${CLANG_RESOURCE_DIR}."
    echo "Install the clang runtime package for clang ${CLANG_VERSION} (e.g., clang-rt-${CLANG_VERSION} or libclang-rt-${CLANG_VERSION}-dev)."
    exit 1
  fi
  RUST_SYSROOT="$(rustc --print sysroot)"
  BINDGEN_BIN="$(command -v bindgen)"
  RUSTFMT_BIN="$(command -v rustfmt)"
  RUSTFMT_VERSION="$(rustfmt --version 2>/dev/null || true)"
  if [ -n "$RUSTFMT_VERSION" ] && echo "$RUSTFMT_VERSION" | grep -q "nightly"; then
    export RUSTFMT_UNSTABLE_FEATURES=1
  fi
  BINDGEN_ROOT="${WORKDIR}/bindgen-root"
  mkdir -p "${BINDGEN_ROOT}/bin"
  ln -sf "${BINDGEN_BIN}" "${BINDGEN_ROOT}/bin/bindgen"
  ln -sf "${RUSTFMT_BIN}" "${BINDGEN_ROOT}/bin/rustfmt"

  find_libclang_dir() {
    local candidate
    for candidate in \
      "${CLANG_BASE_PATH}/lib" \
      "/usr/lib/llvm-${CLANG_VERSION}/lib" \
      "/usr/lib/llvm-${CLANG_VERSION}/lib64" \
      "/usr/lib"; do
      if ls "${candidate}"/libclang.so* >/dev/null 2>&1; then
        echo "${candidate}"
        return 0
      fi
    done
    return 1
  }

  LIBCLANG_DIR="$(find_libclang_dir || true)"
  if [ -z "$LIBCLANG_DIR" ]; then
    echo "Unable to locate libclang shared library. Install libclang-dev."
    exit 1
  fi
  ln -sfn "${LIBCLANG_DIR}" "${BINDGEN_ROOT}/lib"
  export LIBCLANG_PATH="${LIBCLANG_DIR}"

  RUST_BINDGEN_ROOT="${BINDGEN_ROOT}"
  RUSTC_VERSION="$(rustc --version)"

  resolve_tool() {
    local preferred="$1"
    local fallback="$2"
    if [ -n "$CLANG_BASE_PATH" ] && [ -x "${CLANG_BASE_PATH}/bin/${preferred}" ]; then
      echo "${CLANG_BASE_PATH}/bin/${preferred}"
      return 0
    fi
    if command -v "$preferred" >/dev/null 2>&1; then
      command -v "$preferred"
      return 0
    fi
    if [ -n "$fallback" ] && command -v "$fallback" >/dev/null 2>&1; then
      command -v "$fallback"
      return 0
    fi
    return 1
  }

  CC="$(resolve_tool clang "")" || {
    echo "Unable to locate clang."
    exit 1
  }
  CXX="$(resolve_tool clang++ "")" || {
    echo "Unable to locate clang++."
    exit 1
  }
  AR="$(resolve_tool llvm-ar ar)" || true
  NM="$(resolve_tool llvm-nm nm)" || true
  RANLIB="$(resolve_tool llvm-ranlib ranlib)" || true

  export CC CXX AR NM RANLIB
  export BUILD_CC="${BUILD_CC:-$CC}"
  export BUILD_CXX="${BUILD_CXX:-$CXX}"
  export BUILD_AR="${BUILD_AR:-$AR}"
  export BUILD_NM="${BUILD_NM:-$NM}"
  export BUILD_RANLIB="${BUILD_RANLIB:-$RANLIB}"
  # Allow Chromium's required nightly-only rustc flags on Debian stable toolchains.
  export RUSTC_BOOTSTRAP=1
fi

readonly DOWNLOAD_CACHE="${UGC_DOWNLOAD_CACHE:-$UGC_BUILD_DIR/download_cache}"
readonly CHROMIUM_SRC="${CHROMIUM_SRC:-$UGC_BUILD_DIR/src}"
readonly CHROMIUM_OUT="${CHROMIUM_OUT:-$CHROMIUM_SRC/out/Default}"

if [ ! -d "$DOWNLOAD_CACHE" ] && [ -d "$UGC_REPO/build/download_cache" ]; then
  mkdir -p "$DOWNLOAD_CACHE"
  cp -a "$UGC_REPO/build/download_cache/." "$DOWNLOAD_CACHE/"
fi
mkdir -p "$DOWNLOAD_CACHE"

echo "Fetching Chromium source via ungoogled-chromium utils..."
python3 "$UGC_REPO/utils/downloads.py" retrieve -c "$DOWNLOAD_CACHE" -i "$UGC_REPO/downloads.ini"
rm -rf "$CHROMIUM_SRC"
python3 "$UGC_REPO/utils/downloads.py" unpack -c "$DOWNLOAD_CACHE" -i "$UGC_REPO/downloads.ini" -- "$CHROMIUM_SRC"

check_build_deps() {
  local deps_py="$CHROMIUM_SRC/build/install-build-deps.py"
  if [ ! -f "$deps_py" ]; then
    echo "Unable to locate Chromium dependency list at $deps_py"
    exit 1
  fi

  local deps_output=""
  deps_output="$(python3 - "$deps_py" <<'PY'
import importlib.util
import shutil
import subprocess
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("deps", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

options = mod.parse_args([])
packages = mod.package_list(options)

# Printing is disabled; do not require CUPS packages. Also drop cross-toolchain
# and test-runner packages that are not needed for a Debian x86_64 local build.
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
    "lighttpd",
    "xserver-xorg-video-dummy",
    "xvfb",
      "rpm",
      "cdbs",
    "devscripts",
}

replace_map = {
    "libasound2": "libasound2t64",
    "libatk1.0-0": "libatk1.0-0t64",
    "libatspi2.0-0": "libatspi2.0-0t64",
    "libbrlapi0.5": "libbrlapi0.8",
    "libgtk-3-0": "libgtk-3-0t64",
    "libjpeg62-dev": "libjpeg62-turbo-dev",
    "libjpeg62": "libjpeg62-turbo",
    "libncurses5": "libncurses6",
    "libnspr4-0d": "libnspr4",
    "libnss3-1d": "libnss3",
    "libpng12-0": "libpng16-16",
}

def candidate_exists(pkg):
    result = subprocess.run(
        ["apt-cache", "policy", pkg],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    for line in result.stdout.splitlines():
        if line.strip().startswith("Candidate:"):
            return "(none)" not in line
    return False

resolved = []
missing_candidates = []
for pkg in packages:
    if pkg in exclude:
        continue
    mapped = replace_map.get(pkg, pkg)
    if mapped != pkg and candidate_exists(mapped):
        resolved.append(mapped)
        continue
    if candidate_exists(pkg):
        resolved.append(pkg)
        continue
    missing_candidates.append(pkg)

packages = resolved
for pkg in include:
    if pkg in packages:
        continue
    if candidate_exists(pkg):
        packages.append(pkg)
    else:
        missing_candidates.append(pkg)
if shutil.which("git"):
    exclude.add("git-core")
def missing_packages(pkgs):
    if not pkgs:
        return []
    cmd = ["dpkg-query", "-W", "-f=${Package}\t${Status}\n", *pkgs]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    out = result.stdout
    missing = []
    seen = set()
    for line in out.splitlines():
        if not line.strip():
            continue
        name, status = line.split("\t", 1)
        seen.add(name)
        if "install ok installed" not in status:
            missing.append(name)
    for pkg in pkgs:
        if pkg not in seen:
            missing.append(pkg)
    return missing

missing = missing_packages(packages)
if missing_candidates:
    for pkg in sorted(set(missing_candidates)):
        print(f"# no candidate: {pkg}", file=sys.stderr)
for pkg in missing:
    print(pkg)
PY
  )" || {
    echo "Dependency preflight failed."
    exit 1
  }
  mapfile -t missing_pkgs <<<"$deps_output"
  # Drop empty lines just in case.
  local filtered=()
  local pkg
  for pkg in "${missing_pkgs[@]}"; do
    if [ -n "$pkg" ]; then
      filtered+=("$pkg")
    fi
  done
  missing_pkgs=("${filtered[@]}")

  if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    echo "Missing required Debian packages:"
    printf '  - %s\n' "${missing_pkgs[@]}"
    echo ""
    echo "Install with:"
    local install_cmd
    install_cmd="$(printf '%s ' "${missing_pkgs[@]}")"
    install_cmd="${install_cmd% }"
    echo "  sudo apt-get install -y ${install_cmd}"
    exit 1
  fi
}

check_build_deps

python3 "$UGC_REPO/utils/prune_binaries.py" "$CHROMIUM_SRC" "$UGC_REPO/pruning.list"
NODE_BIN="$(command -v node || true)"
if [ -n "$NODE_BIN" ]; then
  NODE_REAL="$(readlink -f "$NODE_BIN" 2>/dev/null || true)"
  if [ -z "$NODE_REAL" ]; then
    NODE_REAL="$NODE_BIN"
  fi
  NODE_TARGET="$CHROMIUM_SRC/third_party/node/linux/node-linux-x64/bin/node"
  mkdir -p "$(dirname "$NODE_TARGET")"
  ln -sf "$NODE_REAL" "$NODE_TARGET"
  export CHROMIUM_USE_SYSTEM_NODE=1
  echo "Using system Node.js at ${NODE_REAL}."
fi
python3 "$UGC_REPO/utils/patches.py" apply "$CHROMIUM_SRC" "$UGC_REPO/patches"
rm -f "$UGC_BUILD_DIR/domsubcache.tar.gz"
python3 "$UGC_REPO/utils/domain_substitution.py" apply \
  -r "$UGC_REPO/domain_regex.list" \
  -f "$UGC_REPO/domain_substitution.list" \
  -c "$UGC_BUILD_DIR/domsubcache.tar.gz" \
  "$CHROMIUM_SRC"

apply_patch_file() {
  local patch_file="$1"
  if [ ! -f "$patch_file" ]; then
    echo "Missing patch: $patch_file"
    exit 1
  fi
  local base_patch
  base_patch="$(basename "$patch_file")"
  local skip_patch
  for skip_patch in "${SKIP_PATCHES[@]}"; do
    if [ "$base_patch" = "$skip_patch" ]; then
      echo "Skipping obsolete patch: $base_patch"
      return 0
    fi
  done
  if command -v git >/dev/null 2>&1; then
    local rel_chromium=""
    local git_apply=()
    if [ "$CHROMIUM_SRC" = "$REPO_ROOT" ]; then
      git_apply=(git -C "$CHROMIUM_SRC" apply -p1 --whitespace=nowarn)
    elif [ "${CHROMIUM_SRC#"$REPO_ROOT"/}" != "$CHROMIUM_SRC" ]; then
      rel_chromium="${CHROMIUM_SRC#"$REPO_ROOT"/}"
      git_apply=(git -C "$REPO_ROOT" apply -p1 --whitespace=nowarn --directory="$rel_chromium")
    fi

    if [ "${#git_apply[@]}" -gt 0 ]; then
      if "${git_apply[@]}" --check --reverse "$patch_file" >/dev/null 2>&1; then
        echo "Skipping already-applied patch: $(basename "$patch_file")"
        return 0
      fi
      if "${git_apply[@]}" --check "$patch_file" >/dev/null 2>&1; then
        "${git_apply[@]}" "$patch_file"
        return 0
      fi
      echo "Failed to apply patch: $patch_file"
      "${git_apply[@]}" --check "$patch_file" || true
      exit 1
    fi
  fi

  if (cd "$CHROMIUM_SRC" && patch -p1 --dry-run -R < "$patch_file" >/dev/null 2>&1); then
    echo "Skipping already-applied patch: $(basename "$patch_file")"
    return 0
  fi
  if (cd "$CHROMIUM_SRC" && patch -p1 --dry-run < "$patch_file"); then
    (cd "$CHROMIUM_SRC" && patch -p1 < "$patch_file")
    return 0
  fi
  echo "Failed to apply patch: $patch_file"
  exit 1
}

apply_patch_list() {
  local label="$1"
  shift
  local patch
  for patch in "$@"; do
    echo "Applying ${label} patch: $(basename "$patch")"
    apply_patch_file "$patch"
  done
}

mapfile -t VANADIUM_PATCHES < <(find "$REPO_ROOT/vanadium_patches" -maxdepth 1 -type f -name '*.patch' -print | LC_ALL=C sort)
mapfile -t TRIVALENT_PATCHES < <(
  find "$REPO_ROOT/patches" -maxdepth 1 -type f -name '*.patch' -print
  find "$REPO_ROOT/translation_patches" -maxdepth 1 -type f -name '*.patch' -print
  find "$REPO_ROOT/translation_patches/translations" -maxdepth 1 -type f -name '*.patch' -print
)
mapfile -t TRIVALENT_PATCHES_SORTED < <(printf '%s\n' "${TRIVALENT_PATCHES[@]}" | LC_ALL=C sort)

apply_patch_list "Vanadium" "${VANADIUM_PATCHES[@]}"
apply_patch_list "Trivalent" "${TRIVALENT_PATCHES_SORTED[@]}"

mkdir -p "$CHROMIUM_OUT"

GN_BOOTSTRAP="$CHROMIUM_SRC/tools/gn/bootstrap/bootstrap.py"
GN_BIN="$CHROMIUM_OUT/gn"
if [ ! -x "$GN_BIN" ]; then
  if [ -f "$GN_BOOTSTRAP" ]; then
    echo "Bootstrapping GN..."
    python3 "$GN_BOOTSTRAP" --skip-generate-buildfiles -j"${GN_BOOTSTRAP_JOBS:-4}" -o "$CHROMIUM_OUT/"
  fi
fi
if [ ! -x "$GN_BIN" ]; then
  echo "GN binary not found at $GN_BIN"
  exit 1
fi

if [ "${USE_SYSTEM_TOOLCHAIN}" != "1" ]; then
  if [ ! -x "$CHROMIUM_SRC/third_party/llvm-build/Release+Asserts/bin/clang" ]; then
    if [ -x "$CHROMIUM_SRC/tools/clang/scripts/update.py" ]; then
      echo "Fetching Chromium clang toolchain..."
      python3 "$CHROMIUM_SRC/tools/clang/scripts/update.py"
    else
      echo "Bundled clang toolchain is missing. Install clang and set USE_SYSTEM_TOOLCHAIN=1."
      exit 1
    fi
  fi
fi

detect_libdir() {
  local multiarch=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi
  if [ -z "$multiarch" ] && command -v gcc >/dev/null 2>&1; then
    multiarch="$(gcc -print-multiarch 2>/dev/null || true)"
  fi
  if [ -n "$multiarch" ] && [ -d "/usr/lib/$multiarch" ]; then
    echo "/usr/lib/$multiarch"
    return 0
  fi
  if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
    echo "/usr/lib/x86_64-linux-gnu"
    return 0
  fi
  echo "/usr/lib"
}

readonly SYSTEM_LIBDIR="$(detect_libdir)"

QT_MOC_PATH=""
if [ -x "/usr/lib/qt6/libexec/moc" ]; then
  QT_MOC_PATH="/usr/lib/qt6/libexec/"
elif [ -x "${SYSTEM_LIBDIR}/qt6/libexec/moc" ]; then
  QT_MOC_PATH="${SYSTEM_LIBDIR}/qt6/libexec/"
elif command -v moc-qt6 >/dev/null 2>&1; then
  QT_MOC_PATH="$(dirname "$(command -v moc-qt6)")/../libexec/"
fi

USE_QT6="${USE_QT6:-auto}"
if [ "$USE_QT6" = "auto" ]; then
  if [ -n "$QT_MOC_PATH" ]; then
    USE_QT6="1"
  else
    USE_QT6="0"
  fi
fi

if [ "${TRIVALENT_MARCH_NATIVE:-1}" = "1" ]; then
  CFLAGS="${CFLAGS:-} -march=native -mtune=native"
  CXXFLAGS="${CXXFLAGS:-} -march=native -mtune=native"
  BUILD_CFLAGS="${BUILD_CFLAGS:-} -march=native -mtune=native"
  BUILD_CXXFLAGS="${BUILD_CXXFLAGS:-} -march=native -mtune=native"
  export CFLAGS CXXFLAGS BUILD_CFLAGS BUILD_CXXFLAGS
fi

cp "$UGC_REPO/flags.gn" "$CHROMIUM_OUT/args.gn"
cat >> "$CHROMIUM_OUT/args.gn" <<EOF
is_official_build=true
is_cfi=true
use_cfi_cast=true
is_clang=true
use_lld=true
use_sysroot=false
clang_warning_suppression_file=""
clang_unsafe_buffers_paths=""
target_os="linux"
current_os="linux"
treat_warnings_as_errors=false
enable_vr=false
use_static_angle=true
angle_shared_libvulkan=false
enable_swiftshader=false
build_dawn_tests=false
enable_perfetto_unittests=false
disable_fieldtrial_testing_config=true
symbol_level=0
blink_symbol_level=0
angle_has_histograms=false
safe_browsing_use_unrar=false
enable_reporting=false
enable_remoting=false
enable_printing=false
use_cups=false
use_cups_ipp=false
use_kerberos=true
use_pulseaudio=true
rtc_use_pipewire=true
rtc_link_pipewire=true
v8_enable_drumbrake=true
ffmpeg_branding="Chromium"
proprietary_codecs=false
enable_widevine=false
system_libdir="${SYSTEM_LIBDIR}"
EOF

if [ "${USE_SYSTEM_TOOLCHAIN}" = "1" ]; then
  cat >> "$CHROMIUM_OUT/args.gn" <<EOF
custom_toolchain="//build/toolchain/linux/unbundle:default"
host_toolchain="//build/toolchain/linux/unbundle:default"
clang_base_path="${CLANG_BASE_PATH}"
clang_version=${CLANG_VERSION}
clang_use_chrome_plugins=false
rust_sysroot_absolute="${RUST_SYSROOT}"
rust_bindgen_root="${RUST_BINDGEN_ROOT}"
rustc_version="${RUSTC_VERSION}"
chrome_pgo_phase=0
EOF
fi

if [ "$USE_QT6" = "1" ]; then
  echo "use_qt6=true" >> "$CHROMIUM_OUT/args.gn"
  if [ -n "$QT_MOC_PATH" ]; then
    echo "moc_qt6_path=\"${QT_MOC_PATH}\"" >> "$CHROMIUM_OUT/args.gn"
  fi
else
  echo "use_qt6=false" >> "$CHROMIUM_OUT/args.gn"
fi

"$GN_BIN" gen "$CHROMIUM_OUT" --root="$CHROMIUM_SRC" --fail-on-unused-args
ninja -C "$CHROMIUM_OUT" chrome

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

readonly CHROMIUM_NAME="trivalent"
readonly CHROMIUM_PATH="${SYSTEM_LIBDIR}/${CHROMIUM_NAME}"

mkdir -p \
  "$INSTALL_DIR/usr/bin" \
  "$INSTALL_DIR${CHROMIUM_PATH}/locales" \
  "$INSTALL_DIR/etc/${CHROMIUM_NAME}" \
  "$INSTALL_DIR/etc/${CHROMIUM_NAME}/${CHROMIUM_NAME}.conf.d" \
  "$INSTALL_DIR/etc/${CHROMIUM_NAME}/policies/managed" \
  "$INSTALL_DIR/etc/${CHROMIUM_NAME}/policies/recommended" \
  "$INSTALL_DIR/usr/share/applications" \
  "$INSTALL_DIR/usr/share/metainfo" \
  "$INSTALL_DIR/usr/share/mime/packages" \
  "$INSTALL_DIR/usr/share/icons/hicolor/24x24/apps" \
  "$INSTALL_DIR/usr/share/icons/hicolor/48x48/apps" \
  "$INSTALL_DIR/usr/share/icons/hicolor/64x64/apps" \
  "$INSTALL_DIR/usr/share/icons/hicolor/128x128/apps" \
  "$INSTALL_DIR/usr/share/icons/hicolor/256x256/apps"

cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}.conf" \
  "$INSTALL_DIR/etc/${CHROMIUM_NAME}/${CHROMIUM_NAME}.conf"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}.sh" \
  "$INSTALL_DIR${CHROMIUM_PATH}/${CHROMIUM_NAME}.sh"

BUILD_TARGET="Debian (local build)"
if [ -r /etc/os-release ]; then
  # shellcheck source=/etc/os-release
  . /etc/os-release
  if [ -n "${PRETTY_NAME:-}" ]; then
    BUILD_TARGET="${PRETTY_NAME}"
  elif [ -n "${NAME:-}" ]; then
    BUILD_TARGET="${NAME}"
  fi
fi

sed -i "s|@@BUILD_TARGET@@|${BUILD_TARGET}|g" \
  "$INSTALL_DIR${CHROMIUM_PATH}/${CHROMIUM_NAME}.sh"
sed -i "s|@@CHROMIUM_NAME@@|${CHROMIUM_NAME}|g" \
  "$INSTALL_DIR${CHROMIUM_PATH}/${CHROMIUM_NAME}.sh"

ln -s "../..${CHROMIUM_PATH}/${CHROMIUM_NAME}.sh" \
  "$INSTALL_DIR/usr/bin/${CHROMIUM_NAME}"

cp -a "$CHROMIUM_OUT/icudtl.dat" "$INSTALL_DIR${CHROMIUM_PATH}/"
cp -a "$CHROMIUM_OUT"/chrom*.pak "$INSTALL_DIR${CHROMIUM_PATH}/"
cp -a "$CHROMIUM_OUT/resources.pak" "$INSTALL_DIR${CHROMIUM_PATH}/"
cp -a "$CHROMIUM_OUT/locales/"*.pak "$INSTALL_DIR${CHROMIUM_PATH}/locales/"
cp -a "$CHROMIUM_OUT/chrome" "$INSTALL_DIR${CHROMIUM_PATH}/${CHROMIUM_NAME}"
cp -a "$CHROMIUM_OUT/chrome_crashpad_handler" "$INSTALL_DIR${CHROMIUM_PATH}/"
cp -a "$CHROMIUM_OUT/v8_context_snapshot.bin" "$INSTALL_DIR${CHROMIUM_PATH}/"

if [ -f "$CHROMIUM_OUT/libqt6_shim.so" ]; then
  cp -a "$CHROMIUM_OUT/libqt6_shim.so" "$INSTALL_DIR${CHROMIUM_PATH}/"
fi

cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}.desktop" \
  "$INSTALL_DIR/usr/share/applications/${CHROMIUM_NAME}.desktop"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}.appdata.xml" \
  "$INSTALL_DIR/usr/share/metainfo/${CHROMIUM_NAME}.appdata.xml"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}.xml" \
  "$INSTALL_DIR/usr/share/mime/packages/${CHROMIUM_NAME}.xml"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}24.png" \
  "$INSTALL_DIR/usr/share/icons/hicolor/24x24/apps/${CHROMIUM_NAME}.png"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}48.png" \
  "$INSTALL_DIR/usr/share/icons/hicolor/48x48/apps/${CHROMIUM_NAME}.png"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}64.png" \
  "$INSTALL_DIR/usr/share/icons/hicolor/64x64/apps/${CHROMIUM_NAME}.png"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}128.png" \
  "$INSTALL_DIR/usr/share/icons/hicolor/128x128/apps/${CHROMIUM_NAME}.png"
cp -a "$REPO_ROOT/build/${CHROMIUM_NAME}256.png" \
  "$INSTALL_DIR/usr/share/icons/hicolor/256x256/apps/${CHROMIUM_NAME}.png"

if [ "${STRIP_BINARIES:-1}" = "1" ] && command -v strip >/dev/null 2>&1; then
  strip "$INSTALL_DIR${CHROMIUM_PATH}/${CHROMIUM_NAME}" || true
  strip "$INSTALL_DIR${CHROMIUM_PATH}/chrome_crashpad_handler" || true
fi

echo "Build complete."
echo "Install tree: $INSTALL_DIR"
