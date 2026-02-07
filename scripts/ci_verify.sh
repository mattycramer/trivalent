#!/usr/bin/env bash
set -euo pipefail

python3 -m compileall -q scripts
bash -n debian_build.sh

version="$(python3 scripts/trivalent_version.py get)"
ci_version="$(python3 - <<'PY'
import re
from pathlib import Path

text = Path('.gitlab-ci.yml').read_text(encoding='utf-8')
match = re.search(r'^\s*RELEASE_VERSION:\s*["\']?([0-9]+\.[0-9]+\.[0-9]+)', text, re.M)
if not match:
    raise SystemExit('RELEASE_VERSION not found in .gitlab-ci.yml')
print(match.group(1))
PY
)"

if [ "${version}" != "${ci_version}" ]; then
  echo "VERSION (${version}) does not match .gitlab-ci.yml RELEASE_VERSION (${ci_version})." >&2
  exit 1
fi
