#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"

xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_ID_PASSWORD"

xcrun notarytool submit "build_output/Osaurus-${VERSION}.dmg" \
  --keychain-profile "AC_PASSWORD" \
  --wait \
  --timeout 30m

xcrun stapler staple "build_output/Osaurus-${VERSION}.dmg"
cp "build_output/Osaurus-${VERSION}.dmg" "build_output/Osaurus.dmg"


