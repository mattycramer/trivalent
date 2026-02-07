# AGENTS.md (repo)

## Scope
This fork targets **Debian x86_64 only** and is built locally from an
ungoogled-chromium source tarball. Apply these rules for all edits in this repo.

## Priorities
1) Correctness
2) Security
3) Performance
4) Maintainability
5) Polish

## Branching & release rules (mandatory)
- **Source of truth:** All changes must be fetched from the GitLab `origin` remote.
- **No direct changes on `github/mcr/main`:** treat it as a read-only mirror.
- **Forward flow:** `mcr/main` must be merged/forwarded into `mcr/staging`, then
  `mcr/release`. Keep `mcr/main`, `mcr/staging`, and `mcr/release` aligned.
- **Lockstep:** after each forward merge, `mcr/main`, `mcr/staging`, and
  `mcr/release` must point to the **same commit**.
- **Feature branches:** create `mcr/feature/*` from `mcr/main` (after forward
  syncing `github/mcr/main` → `mcr/main`), then merge/forward into `mcr/main`.

## Patch workflow (mandatory)
- New implementations that touch Chromium sources **must** be added as
  `patches/*.patch` instead of direct edits to upstream files.
- **Exceptions:** direct edits are allowed only in `.gitlab-ci.yml`, `.github/*`,
  and `scripts/*`.

## Testing rules
- Testing **always** runs on `mcr/staging` via the GitLab pipeline.
- The authoritative test commands live in `.gitlab-ci.yml`.
- Do not add Rust/Cargo test pipelines unless the repo contains a Cargo project.

## Deployment rules
- `mcr/release` is the deployment branch.
- GitLab CI handles verify/version/push and syncs `mcr/release` to GitHub.
- `GIT_BRANCH_PREFIX` and `GIT_BRANCH_RELEASE` are provided via Bitwarden
  Secrets Manager in the shared GitLab pipeline; **do not** set them in
  `.gitlab-ci.yml`.
- Tags starting with `gl-` must be created **on the tip of `mcr/release`** and
  pushed to GitHub.
- Tag format for releases: `gl-trivalent-vX.Y.Z` (optional `-rN` suffix).
- GitHub Actions **must** build Debian tarballs for `gl-*` tags only.
- GitHub builds must target **modern Debian x86_64 only** (no Fedora/COPR,
  no multi-arch builds, no Docker-based build pipeline in GitHub Actions).

## Versioning
- Release version is tracked in `VERSION` and must be updated using
  `scripts/bump_version.py`.
- Keep `.gitlab-ci.yml` `RELEASE_VERSION` in sync with `VERSION`.

## Debian porting guidance
- Debian-only: do not add Fedora/COPR workflows or fallbacks.
- Debian builds must use ungoogled-chromium as the upstream source tarball
  (currently 144.0.7559.109-1).
- Do **not** enable proprietary codecs or Widevine; default to a fully free,
  hardened build.
- Printing is disabled on Debian (`enable_printing=false`, `use_cups=false`);
  do not require CUPS.
- Use multiarch-aware libdir detection (`/usr/lib/x86_64-linux-gnu`) and do
  not reintroduce `/usr/lib64`.
- Build artifacts should live under `out/` and must never be committed.
- The RPM spec and COPR script are retained for reference only and are disabled
  in this fork.

## Build requirements (Debian)
- Use the system toolchain: `clang`, `lld`, `rustc`, `bindgen`, `python3`,
  `ninja`, `node`, `pkg-config`, and standard Chromium build deps.
- Default build is hardened and performance-oriented. Keep the following GN
  flags set in the Debian build:
  - `is_official_build=true`
  - `is_cfi=true` and `use_cfi_cast=true`
  - `use_lld=true`, `use_sysroot=false`
  - `ffmpeg_branding="Chromium"`, `proprietary_codecs=false`,
    `enable_widevine=false`
  - `symbol_level=0`, `blink_symbol_level=0`
  - `enable_reporting=false`, `enable_remoting=false`

## Documentation
- Update `docs/` when build steps, flags, or supported platforms change.
