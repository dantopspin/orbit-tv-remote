#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 /path/to/binary [hopper|ghidra|ida]" >&2
  exit 64
fi

target="$1"
provider="${2:-ghidra}"

if [ ! -f "$target" ]; then
  echo "Binary not found: $target" >&2
  exit 66
fi

case "$provider" in
  hopper|ghidra|ida) ;;
  *)
    echo "Unsupported provider: $provider" >&2
    exit 64
    ;;
esac

mkdir -p Tools/REA/output Tools/REA/snapshots

base="$(basename "$target")"
safe_base="$(printf '%s' "$base" | tr -cs 'A-Za-z0-9._-' '_')"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
snapshot="Tools/REA/snapshots/${safe_base}-$provider.json"
output="Tools/REA/output/${safe_base}-$provider-$timestamp.json"

echo "Analyzing native target read-only:"
echo "  $target"
echo "Provider:"
echo "  $provider"
echo "Snapshot:"
echo "  $snapshot"
echo

npx -y rea-agents@latest analyze   "$target"   --provider "$provider"   --snapshot "$snapshot"   --json > "$output"

echo "Saved: $output"
