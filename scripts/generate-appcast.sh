#!/usr/bin/env bash
# scripts/generate-appcast.sh — Generate a Sparkle appcast.xml for a release.
#
# Usage:
#   ./scripts/generate-appcast.sh <dmg-path> <version> [download-url]
#
# Env:
#   SPARKLE_ED25519_PRIVATE_KEY  base64-encoded ed25519 private key (.pem contents)
#                                Required. Local dev can pass --ed-key-file flag
#                                via sign_update directly instead.
#   APPCAST_TITLE                Channel title (default: "Genesis Imaging")
#   APPCAST_DESCRIPTION          Channel description
#
# Output: appcast.xml content written to stdout.
#
# The script depends on Sparkle's `sign_update` CLI being available at
# .build/artifacts/sparkle/Sparkle/bin/sign_update — that path is populated
# automatically after `swift build` (or `swift package resolve`) runs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="${ROOT}/.build/artifacts/sparkle/Sparkle/bin/sign_update"

DMG_PATH="${1:?Usage: $0 <dmg-path> <version> [download-url]}"
VERSION="${2:?Usage: $0 <dmg-path> <version> [download-url]}"
DOWNLOAD_URL="${3:-https://github.com/Software-As-An-AI/genesis-imaging/releases/download/v${VERSION}/$(basename "$DMG_PATH")}"

CHANNEL_TITLE="${APPCAST_TITLE:-Genesis Imaging}"
CHANNEL_DESCRIPTION="${APPCAST_DESCRIPTION:-On-device image upscaling for macOS. Updates feed.}"

# ── Verify inputs ──────────────────────────────────────────────────────────
if [ ! -f "$DMG_PATH" ]; then
    echo "[generate-appcast] ✗ DMG not found: $DMG_PATH" >&2
    exit 1
fi
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "[generate-appcast] ✗ Sparkle sign_update binary not found at $SIGN_UPDATE" >&2
    echo "[generate-appcast]   Run 'swift package resolve' first to fetch Sparkle artifacts." >&2
    exit 1
fi
if [ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]; then
    echo "[generate-appcast] ✗ SPARKLE_ED25519_PRIVATE_KEY env var required" >&2
    echo "[generate-appcast]   Expected: base64-encoded ed25519 private key (.pem contents)" >&2
    exit 1
fi

# ── Write private key to temp file (sign_update reads file, not env) ───────
# Sparkle's `generate_keys -x` exports the 32-byte ed25519 seed already
# base64-encoded as a 44-char text file. `sign_update --ed-key-file` reads
# that same format — so we write the secret value AS-IS without decoding.
# (An earlier draft of this script base64-decoded the value into raw bytes,
# which made sign_update fail with "Unable to read EdDSA private key data
# as UTF-8 string". The secret stored in GitHub Actions is already the
# base64 text produced by `generate_keys -x`.)
PRIV_KEY_FILE=$(mktemp -t sparkle-priv.XXXXXX)
trap 'rm -f "$PRIV_KEY_FILE"' EXIT INT TERM
printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" > "$PRIV_KEY_FILE"

# Verify the key file has content (wisdom_d4fda9ab — defensive against
# empty-secret silent fail). Local export is 44 bytes (base64 of 32-byte seed).
PRIV_KEY_SIZE=$(wc -c < "$PRIV_KEY_FILE" | tr -d ' ')
if [ "$PRIV_KEY_SIZE" -lt 40 ] || [ "$PRIV_KEY_SIZE" -gt 60 ]; then
    echo "[generate-appcast] ✗ private key size suspicious ($PRIV_KEY_SIZE bytes, expected ~44) — check SPARKLE_ED25519_PRIVATE_KEY secret" >&2
    exit 1
fi

# ── Sign the DMG ────────────────────────────────────────────────────────────
# sign_update without -p emits the full XML attribute string for the
# <enclosure> element: `sparkle:edSignature="..." length="..."`.
# Using -p prints only the signature value (no attribute name/quoting),
# which produced invalid XML when interpolated into the template.
SIGNATURE_INFO=$("$SIGN_UPDATE" --ed-key-file "$PRIV_KEY_FILE" "$DMG_PATH")

if [ -z "$SIGNATURE_INFO" ]; then
    echo "[generate-appcast] ✗ sign_update produced no output" >&2
    exit 1
fi
# Verify the expected attribute keywords are in the signature output.
if ! echo "$SIGNATURE_INFO" | grep -q 'sparkle:edSignature='; then
    echo "[generate-appcast] ✗ sign_update output missing sparkle:edSignature= attribute" >&2
    echo "[generate-appcast]   got: $SIGNATURE_INFO" >&2
    exit 1
fi

# ── Build appcast.xml ──────────────────────────────────────────────────────
PUB_DATE=$(date -R 2>/dev/null || date -u "+%a, %d %b %Y %H:%M:%S %z")
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH")
MIN_SYSTEM_VERSION="14.0"

cat << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${CHANNEL_TITLE}</title>
    <link>https://apps.softwareasan.ai/genesis-imaging/appcast.xml</link>
    <description>${CHANNEL_DESCRIPTION}</description>
    <language>tr</language>
    <item>
      <title>Genesis Imaging ${VERSION}</title>
      <link>https://github.com/Software-As-An-AI/genesis-imaging/releases/tag/v${VERSION}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        <p>Genesis Imaging v${VERSION} — release notes:
        <a href="https://github.com/Software-As-An-AI/genesis-imaging/releases/tag/v${VERSION}">github.com/Software-As-An-AI/genesis-imaging/releases/tag/v${VERSION}</a></p>
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        type="application/octet-stream"
        ${SIGNATURE_INFO} />
    </item>
  </channel>
</rss>
APPCAST_EOF
