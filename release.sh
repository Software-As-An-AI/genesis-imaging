#!/usr/bin/env bash
# Genesis Imaging Release Script (adapted from sendikaos-v2/release.sh)
#
# Usage:
#   ./release.sh           — Auto-increment patch (v1.3.25 → v1.3.26)
#   ./release.sh v1.4.0    — Specific version
#   ./release.sh minor     — Bump minor
#   ./release.sh major     — Bump major

set -e

cd "$(dirname "$0")"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ── Sync tags from remote ───────────────────────────────────────────────────
echo -e "${DIM}Tag'ler senkronize ediliyor...${NC}"
git fetch --tags --force --quiet 2>/dev/null

LATEST_TAG=$(git tag -l 'v*.*.*' --sort=-version:refname | head -1)
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v0.0.0"
fi

VERSION_PART="${LATEST_TAG#v}"
MAJOR=$(echo "$VERSION_PART" | cut -d. -f1)
MINOR=$(echo "$VERSION_PART" | cut -d. -f2)
PATCH=$(echo "$VERSION_PART" | cut -d. -f3)

# ── Determine new version ──────────────────────────────────────────────────
NEW_TAG=""
case "${1:-patch}" in
    major)
        MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor)
        MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch|"")
        PATCH=$((PATCH + 1)) ;;
    v*)
        NEW_TAG="$1" ;;
    *)
        echo -e "${RED}Kullanım: ./release.sh [patch|minor|major|v1.2.3]${NC}"
        exit 1
        ;;
esac

if [ -z "$NEW_TAG" ]; then
    NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
fi

# ── Tag must not exist ─────────────────────────────────────────────────────
if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
    echo -e "${RED}Tag ${NEW_TAG} zaten mevcut!${NC}"
    echo -e "Mevcut son tag: ${YELLOW}${LATEST_TAG}${NC}"
    exit 1
fi

# ── Auto-commit dirty changes (failsafe) ───────────────────────────────────
DIRTY=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null)
if [ -n "$DIRTY" ]; then
    echo -e "${YELLOW}Commit edilmemis degisiklikler var:${NC}"
    echo "$DIRTY"
    echo ""
    read -p "Commit ederek devam edeyim mi? (y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 1
    fi
    git add -A
    git commit -m "chore: pre-release changes for ${NEW_TAG}"
fi

# ── Ensure pushed ──────────────────────────────────────────────────────────
if [ -n "$(git log @{u}.. 2>/dev/null)" ]; then
    echo -e "${YELLOW}Push edilmemiş commit'ler var, push ediliyor...${NC}"
    git push origin HEAD
fi

# ── Summary ────────────────────────────────────────────────────────────────
COMMIT_COUNT=$(git rev-list --count "${LATEST_TAG}..HEAD" 2>/dev/null || echo "0")
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Release Özeti${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Önceki tag:  ${YELLOW}${LATEST_TAG}${NC}"
echo -e "  Yeni tag:    ${GREEN}${NEW_TAG}${NC}"
echo -e "  Commit:      ${COMMIT_COUNT}"
echo ""
echo -e "${DIM}Son 5 commit:${NC}"
git log --oneline -5 | sed 's/^/  /'
echo ""

read -p "Release devam etsin mi? (y/N) " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "İptal edildi."
    exit 0
fi

# ── Tag + push ─────────────────────────────────────────────────────────────
echo -e "${CYAN}Tag oluşturuluyor: ${NEW_TAG}${NC}"
git tag "$NEW_TAG"
git push origin "$NEW_TAG"

echo ""
echo -e "${GREEN}✓ Tag pushed.${NC}"
echo -e "  GitHub Actions: ${CYAN}https://github.com/Software-As-An-AI/genesis-imaging/actions${NC}"
echo -e "  Releases:       ${CYAN}https://github.com/Software-As-An-AI/genesis-imaging/releases${NC}"
echo ""

# ── Optional: watch the release workflow ────────────────────────────────────
if command -v gh >/dev/null 2>&1; then
    read -p "GitHub Actions Release workflow'unu izleyeyim mi? (y/N) " watch
    if [ "$watch" = "y" ] || [ "$watch" = "Y" ]; then
        echo -e "${DIM}Workflow runs (en son):${NC}"
        sleep 3  # GitHub'ın workflow'u register etmesi için kısa bekleme
        gh run watch --repo Software-As-An-AI/genesis-imaging "$(gh run list --workflow Release --limit 1 --json databaseId --jq '.[0].databaseId')"
    fi
fi
