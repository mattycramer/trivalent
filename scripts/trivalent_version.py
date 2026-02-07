#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def read_version(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Missing version file: {path}")
    version = path.read_text(encoding="utf-8").strip()
    if not SEMVER_RE.match(version):
        raise ValueError(f"Invalid version '{version}' in {path} (expected X.Y.Z)")
    return version


def write_version(path: Path, version: str) -> None:
    if not SEMVER_RE.match(version):
        raise ValueError(f"Version must be X.Y.Z (got: {version})")
    path.write_text(f"{version}\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: trivalent_version.py get | set <version>", file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "get":
        print(read_version(VERSION_FILE))
        return 0
    if cmd == "set" and len(argv) == 3:
        write_version(VERSION_FILE, argv[2])
        return 0
    print("Usage: trivalent_version.py get | set <version>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
