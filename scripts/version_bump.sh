#!/usr/bin/env bash
# scripts/version_bump.sh — Genesis 4-digit versioning adapted for Genesis Imaging
#
# Format: MAJOR.MINOR.PUSH.COMMIT (Genesis-canonical, NOT semver)
#   0.1.2.5 means: minor 1, milestone 2, 5th commit since last push
#
# SSOT: genesis.json (Genesis Imaging is Swift, no pyproject.toml).
#
# Usage:
#   ./scripts/version_bump.sh show              # Show current version with breakdown
#   ./scripts/version_bump.sh commit            # +1 4th digit (commit, post-commit hook)
#   ./scripts/version_bump.sh push              # +1 3rd digit, reset 4th (pre-push hook)
#   ./scripts/version_bump.sh set 0.2           # New milestone, reset push+commit
#   ./scripts/version_bump.sh --dry-run commit  # Preview only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENESIS_JSON="$ROOT/genesis.json"

if [ ! -f "$GENESIS_JSON" ]; then
    echo "[version-bump] ✗ genesis.json missing at $GENESIS_JSON" >&2
    exit 1
fi

# ── Helpers ────────────────────────────────────────────────────────────────

get_version() {
    python3 -c "import json; d=json.load(open('$GENESIS_JSON')); print(d.get('version', '0.0.0.0'))"
}

parse_version() {
    local ver="$1"
    IFS='.' read -ra PARTS <<< "$ver"
    V_MAJOR="${PARTS[0]:-0}"
    V_MINOR="${PARTS[1]:-0}"
    V_PUSH="${PARTS[2]:-0}"
    V_COMMIT="${PARTS[3]:-0}"
}

write_version() {
    local new_ver="$1"
    python3 -c "
import json
with open('$GENESIS_JSON') as f: d = json.load(f)
d['version'] = '$new_ver'
with open('$GENESIS_JSON', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
}

# ── Parse args ─────────────────────────────────────────────────────────────

DRY_RUN=false
ARGS=("$@")
IDX=0

if [ "${ARGS[$IDX]:-}" = "--dry-run" ]; then
    DRY_RUN=true
    IDX=1
fi

ACTION="${ARGS[$IDX]:-show}"
ARG2="${ARGS[$((IDX + 1))]:-}"

# ── Commands ───────────────────────────────────────────────────────────────

case "$ACTION" in
    show)
        VER=$(get_version)
        parse_version "$VER"
        echo "$VER"
        echo "  major.minor: ${V_MAJOR}.${V_MINOR}"
        echo "  pushes:      ${V_PUSH}"
        echo "  commits:     ${V_COMMIT} (since last push)"
        ;;

    commit)
        VER=$(get_version)
        parse_version "$VER"
        NEW_COMMIT=$((V_COMMIT + 1))
        NEW_VER="${V_MAJOR}.${V_MINOR}.${V_PUSH}.${NEW_COMMIT}"
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] ${VER} → ${NEW_VER} (commit +1)"
        else
            write_version "$NEW_VER"
            echo "[VERSION] ${VER} → ${NEW_VER} (commit +1)"
        fi
        ;;

    push)
        VER=$(get_version)
        parse_version "$VER"
        NEW_PUSH=$((V_PUSH + 1))
        NEW_VER="${V_MAJOR}.${V_MINOR}.${NEW_PUSH}.0"
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] ${VER} → ${NEW_VER} (push +1, commit reset)"
        else
            write_version "$NEW_VER"
            echo "[VERSION] ${VER} → ${NEW_VER} (push +1, commit reset)"
        fi
        ;;

    set)
        NEW_BASE="$ARG2"
        if [ -z "$NEW_BASE" ]; then
            echo "Usage: $0 set MAJOR.MINOR" >&2
            echo "Example: $0 set 0.2" >&2
            exit 1
        fi
        IFS='.' read -ra BASE_PARTS <<< "$NEW_BASE"
        if [ ${#BASE_PARTS[@]} -eq 2 ]; then
            NEW_VER="${NEW_BASE}.0.0"
        elif [ ${#BASE_PARTS[@]} -eq 3 ]; then
            NEW_VER="${NEW_BASE}.0"
        else
            NEW_VER="${NEW_BASE}"
        fi
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] → ${NEW_VER} (new milestone)"
        else
            write_version "$NEW_VER"
            echo "[VERSION] → ${NEW_VER} (new milestone)"
        fi
        ;;

    *)
        echo "Usage: $0 [--dry-run] {show|commit|push|set MAJOR.MINOR}" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  show             Show current version with breakdown" >&2
        echo "  commit           Increment 4th digit (commit counter)" >&2
        echo "  push             Increment 3rd (push), reset 4th" >&2
        echo "  set MAJOR.MINOR  New milestone, reset push+commit" >&2
        exit 1
        ;;
esac
