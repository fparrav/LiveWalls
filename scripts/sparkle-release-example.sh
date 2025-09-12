#!/usr/bin/env bash
set -euo pipefail

# Example helper script for Sparkle 2 integration.
# It signs a built app archive and generates an appcast.xml.
#
# Requirements:
# - Sparkle's command line tools installed: `generate_appcast`, `sign_update`
# - Your EdDSA private key stored securely (do NOT commit it)
# - A built DMG or ZIP for LiveWalls
#
# Usage:
#   ./scripts/sparkle-release-example.sh path/to/LiveWalls.dmg https://example.com/livewalls/releases/
# The base URL must match where you will host the artifacts + appcast.xml.

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <artifact.(dmg|zip)> <base_url>"
  exit 1
fi

ARTIFACT_PATH="$1"
BASE_URL="$2"         # e.g. https://example.com/livewalls/releases/
OUTPUT_DIR="dist/sparkle"
APPCAST_TITLE="LiveWalls Updates"

mkdir -p "$OUTPUT_DIR"

echo "Signing update with Sparkle (EdDSA)..."
# Note: SPARKLE_PRIVATE_KEY must point to your private EdDSA key file.
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY env var is not set. Aborting." >&2
  exit 1
fi

# Create a detached signature and write it next to the artifact
sign_update -s "$SPARKLE_PRIVATE_KEY" "$ARTIFACT_PATH"

echo "Generating appcast.xml..."
generate_appcast \
  --download-url-prefix "$BASE_URL" \
  --link "$BASE_URL" \
  --title "$APPCAST_TITLE" \
  --output-dir "$OUTPUT_DIR" \
  "$(dirname "$ARTIFACT_PATH")"

echo "Done. Upload the contents of $OUTPUT_DIR and your artifact to $BASE_URL"
echo "Then set Info.plist: SUFeedURL to ${BASE_URL}appcast.xml and SUPublicEDKey to your public key."

