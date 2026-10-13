#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /absolute/or/repo/path/to/app.apk" >&2
  exit 64
fi

target="$1"

if [ ! -f "$target" ]; then
  echo "APK not found: $target" >&2
  exit 66
fi

case "$target" in
  *.apk) ;;
  *)
    echo "Expected an .apk target: $target" >&2
    exit 64
    ;;
esac

if [ -z "${REA_JADX_MCP_JAR:-}" ]; then
  echo "REA_JADX_MCP_JAR is not set." >&2
  echo "Configure the compatible JADX headless MCP JAR before Android analysis." >&2
  exit 78
fi

mkdir -p Tools/REA/output

base="$(basename "$target" .apk)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="Tools/REA/output/${base}-android-$timestamp.json"

echo "Analyzing Android package read-only:"
echo "  $target"
echo
echo "Output:"
echo "  $output"
echo

npx -y rea-agents@latest inspect-android-package "$target" --json > "$output"

echo "Done."
