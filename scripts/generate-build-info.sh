#!/usr/bin/env bash
# scripts/generate-build-info.sh — Emit BUILD_INFO.json (kulucka pattern, adapted).
#
# Reads version from genesis.json (SSOT), captures git SHA + branch + build host,
# writes to BUILD_INFO.json at repo root. package-app.sh copies it into the .app
# bundle as Resources/BUILD_INFO.json so the running app can read its own provenance.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GENESIS_JSON="$ROOT/genesis.json"
OUT="$ROOT/BUILD_INFO.json"

# VERSION resolution:
#   1. Explicit env override (CI passes ${{ github.ref_name }} stripped)
#   2. genesis.json (Genesis-canonical 4-digit SSOT)
GENESIS_VERSION=$(python3 -c "import json; print(json.load(open('$GENESIS_JSON')).get('version', ''))" 2>/dev/null || echo "")
VERSION="${VERSION:-${GENESIS_VERSION:-0.0.0.0}}"
VERSION="${VERSION#v}"
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
FULL_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_HOST=$(hostname)
CI_RUN_ID="${GITHUB_RUN_ID:-local}"

cat > "$OUT" << EOF
{
  "schema_version": "1.0",
  "genesis_imaging_version": "$VERSION",
  "genesis_imaging_sha": "$SHA",
  "genesis_imaging_full_sha": "$FULL_SHA",
  "genesis_imaging_branch": "$BRANCH",
  "build_date": "$BUILD_DATE",
  "build_host": "$BUILD_HOST",
  "ci_run_id": "$CI_RUN_ID"
}
EOF

echo "[build-info] ✓ $OUT (version=$VERSION sha=$SHA)"
