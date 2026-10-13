#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 short-investigation-name" >&2
  exit 64
fi

name="$1"

if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
  echo "Use only letters, numbers, dot, underscore, and hyphen." >&2
  exit 64
fi

root="Tools/REA/work/$name"

if [ -e "$root" ]; then
  echo "Investigation already exists: $root" >&2
  exit 73
fi

mkdir -p "$root"

cp   Tools/REA/templates/PROTOCOL_INVESTIGATION.md   "$root/README.md"

python3 - "$root/README.md" "$name" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
name = sys.argv[2]

text = path.read_text(encoding="utf-8")
text = text.replace(
    "{{INVESTIGATION_NAME}}",
    name,
)
path.write_text(text, encoding="utf-8")
PY

echo "Created:"
echo "  $root/README.md"
echo
echo "This workspace is ignored by Git."
