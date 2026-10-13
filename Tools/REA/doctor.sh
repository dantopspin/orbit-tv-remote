#!/usr/bin/env bash
set -euo pipefail

mkdir -p Tools/REA/output

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="Tools/REA/output/doctor-$timestamp.json"

echo "Checking REA readiness..."
npx -y rea-agents@latest doctor --json | tee "$output"

echo
echo "Saved: $output"
