#!/usr/bin/env bash
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required for REA." >&2
  exit 1
fi

NODE_VERSION="$(node -p 'process.versions.node')"
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
NODE_MINOR="$(node -p 'Number(process.versions.node.split(".")[1])')"

supported=false

if [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -ge 19 ]; then
  supported=true
elif [ "$NODE_MAJOR" -eq 24 ] && [ "$NODE_MINOR" -ge 11 ]; then
  supported=true
elif [ "$NODE_MAJOR" -ge 26 ]; then
  supported=true
fi

if [ "$supported" != true ]; then
  echo "Unsupported Node.js version: $NODE_VERSION" >&2
  echo "REA currently requires Node 22.19+, Node 24.11+, or Node 26+." >&2
  exit 1
fi

echo "Node.js $NODE_VERSION"
echo
echo "Launching REA's interactive setup."
echo "Review every proposed config/tool change before approving it."
echo

exec npx -y rea-agents@latest setup
