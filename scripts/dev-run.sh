#!/usr/bin/env bash
# scripts/dev-run.sh — One-shot "I want to test my local changes" loop.
#
# What it does (in order):
#   1. Kills any running GenesisImaging instance (packaged /Applications/
#      AND .build/debug binaries). LaunchServices can pick the wrong one
#      otherwise — operator-burn from 2026-05-11 confirmed.
#   2. Regenerates VersionStamp.swift with current git SHA + DEV kind.
#   3. swift build (debug, fast).
#   4. Launches the freshly-built binary directly via its path (bypasses
#      LaunchServices URL-handler routing entirely).
#   5. Prints a loud banner to terminal so it's unmissable which binary
#      is running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "════════════════════════════════════════════════════════════"
echo " Genesis Imaging — DEV RUN"
echo "════════════════════════════════════════════════════════════"

# 1. Kill any running instances (packaged + dev)
PIDS=$(pgrep -f "GenesisImaging" || true)
if [ -n "$PIDS" ]; then
    echo "[dev-run] killing existing GenesisImaging processes: $PIDS"
    # shellcheck disable=SC2086
    kill $PIDS 2>/dev/null || true
    sleep 1
    # SIGKILL stragglers
    PIDS=$(pgrep -f "GenesisImaging" || true)
    if [ -n "$PIDS" ]; then
        # shellcheck disable=SC2086
        kill -9 $PIDS 2>/dev/null || true
    fi
fi

# 2. Stamp version
BUILD_KIND=dev bash "$ROOT/scripts/stamp-version.sh"

# 3. Build (debug, fast iteration)
echo "[dev-run] swift build (debug)"
swift build 2>&1 | tail -20

BIN=".build/debug/GenesisImaging"
if [ ! -x "$BIN" ]; then
    echo "[dev-run] ✗ binary missing at $BIN" >&2
    exit 1
fi

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
DIRTY=""
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then DIRTY=" (dirty)"; fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " ▶  RUNNING DEV BUILD"
echo "    Binary:  $ROOT/$BIN"
echo "    Commit:  $SHA on $BRANCH$DIRTY"
echo "    Kind:    DEV (footer will say 'DEV')"
echo "════════════════════════════════════════════════════════════"
echo ""
echo " ⚠  Packaged /Applications/GenesisImaging.app NOT touched —"
echo "    it stays installed but won't run while this is alive."
echo ""

# 4. Run direct (not via `open` which consults LaunchServices)
exec "$BIN"
