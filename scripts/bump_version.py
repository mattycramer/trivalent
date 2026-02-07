#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
GITLAB_CI = ROOT / ".gitlab-ci.yml"
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bump Trivalent release version.")
    parser.add_argument("--version", required=True, help="Version to set (X.Y.Z)")
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

    print("Updated files:")
    for path in sorted(set(updated_files)):
        print(f" - {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
