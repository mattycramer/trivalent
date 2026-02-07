#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
GITLAB_CI = ROOT / ".gitlab-ci.yml"
DEBIAN_BUILD = ROOT / "debian_build.sh"
DOCKERFILE = ROOT / "Dockerfile"
DOCKER_COMPOSE = ROOT / "docker-compose.yml"
BUILD_DOC = ROOT / "docs" / "BUILDING_DEBIAN.md"
RPM_SPEC = ROOT / "build" / "trivalent.spec"
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
UGC_TAG_RE = re.compile(
    r'^\s*readonly\s+UGC_TAG="\$\{UGC_TAG:-([^}]+)\}"',
    re.MULTILINE,
)
OFF_VERSION_RE = re.compile(
    r'^(?P<prefix>\s*local\s+off_version_tag\s*=\s*")'
    r"(?P<version>[0-9]+\.[0-9]+\.[0-9]+)"
    r"(?P<suffix>[^\"\n]*\")",
    re.MULTILINE,
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bump Trivalent release version.")
    parser.add_argument("--version", required=True, help="Version to set (X.Y.Z)")
    parser.add_argument(
        "--ugc-tag",
        help="Optional ungoogled-chromium tag override (default: update prefix in debian_build.sh).",
    )
    return parser.parse_args(argv)


def read_version(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Missing version file: {path}")
    value = path.read_text(encoding="utf-8").strip()
    if not SEMVER_RE.match(value):
        raise ValueError(f"Invalid version '{value}' in {path} (expected X.Y.Z)")
    return value


def write_version(path: Path, version: str) -> None:
    path.write_text(f"{version}\n", encoding="utf-8")


def update_gitlab_ci(path: Path, new_version: str) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        r"^(\s*RELEASE_VERSION:\s*[\"']?)([0-9]+\.[0-9]+\.[0-9]+)([\"']?\s*)$",
        re.MULTILINE,
    )
    match = pattern.search(text)
    if not match:
        raise ValueError("RELEASE_VERSION not found in .gitlab-ci.yml")
    new_line = f"{match.group(1)}{new_version}{match.group(3)}"
    updated = text[: match.start()] + new_line + text[match.end() :]
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def read_ugc_tag(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Missing build script: {path}")
    text = path.read_text(encoding="utf-8")
    match = UGC_TAG_RE.search(text)
    if not match:
        raise ValueError("UGC_TAG not found in debian_build.sh")
    return match.group(1).strip()


def update_ugc_tag(path: Path, new_tag: str) -> bool:
    text = path.read_text(encoding="utf-8")
    match = UGC_TAG_RE.search(text)
    if not match:
        raise ValueError("UGC_TAG not found in debian_build.sh")
    old_tag = match.group(1)
    updated = text[: match.start(1)] + new_tag + text[match.end(1) :]
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def replace_literal(path: Path, old_value: str, new_value: str) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    if old_value not in text:
        return False
    updated = text.replace(old_value, new_value)
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def update_off_version_tag(path: Path, old_version: str, new_version: str) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    match = OFF_VERSION_RE.search(text)
    if not match:
        return False
    current = match.group("version")
    if current == new_version:
        return False
    if not current.startswith(old_version):
        return False
    updated_version = new_version + current[len(old_version) :]
    updated = (
        text[: match.start("version")] + updated_version + text[match.end("version") :]
    )
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    new_version = args.version.strip()
    if not SEMVER_RE.match(new_version):
        print("Version must be in X.Y.Z format (e.g. 144.0.7559).", file=sys.stderr)
        return 2

    old_version = read_version(VERSION_FILE)
    if old_version == new_version:
        print(f"Version already {new_version}")
        return 0

    updated_files: list[Path] = []

    write_version(VERSION_FILE, new_version)
    updated_files.append(VERSION_FILE)

    if update_gitlab_ci(GITLAB_CI, new_version):
        updated_files.append(GITLAB_CI)

    old_ugc_tag = read_ugc_tag(DEBIAN_BUILD)
    new_ugc_tag = None
    if args.ugc_tag:
        new_ugc_tag = args.ugc_tag.strip()
    elif old_ugc_tag.startswith(old_version):
        new_ugc_tag = new_version + old_ugc_tag[len(old_version) :]
    elif old_ugc_tag.startswith(new_version):
        new_ugc_tag = old_ugc_tag

    if new_ugc_tag and new_ugc_tag != old_ugc_tag:
        if update_ugc_tag(DEBIAN_BUILD, new_ugc_tag):
            updated_files.append(DEBIAN_BUILD)
        for path in (DOCKERFILE, DOCKER_COMPOSE, BUILD_DOC):
            if replace_literal(path, old_ugc_tag, new_ugc_tag):
                updated_files.append(path)
        patches_dir = ROOT / "patches"
        if patches_dir.exists():
            for patch in sorted(patches_dir.glob("*.patch")):
                if replace_literal(patch, old_ugc_tag, new_ugc_tag):
                    updated_files.append(patch)
    elif not new_ugc_tag:
        print(
            f"Warning: UGC_TAG '{old_ugc_tag}' does not start with {old_version}; "
            "leaving ungoogled-chromium tag references unchanged.",
            file=sys.stderr,
        )

    if update_off_version_tag(RPM_SPEC, old_version, new_version):
        updated_files.append(RPM_SPEC)

    print("Updated files:")
    for path in sorted(set(updated_files)):
        print(f" - {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
