#!/usr/bin/env bash
# scripts/build.sh — Compile release executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[build] stamp version (release kind)"
BUILD_KIND=release bash "$ROOT/scripts/stamp-version.sh"

echo "[build] swift build -c release"
swift build -c release

EXEC=".build/release/GenesisImaging"
if [ -x "$EXEC" ]; then
    echo "[build] ✓ $EXEC ($(du -h "$EXEC" | awk '{print $1}'))"
else
    echo "[build] ✗ executable missing at $EXEC" >&2
    exit 1
fi
