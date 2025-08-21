#!/usr/bin/env bash
set -euo pipefail

brew install create-dmg

# ARM64 DMG (no arch suffix)
create-dmg \
  --background "$GITHUB_WORKSPACE/dmg-bg.png" \
  --volname "Osaurus" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "osaurus.app" 150 185 \
  --hide-extension "osaurus.app" \
  --app-drop-link 450 185 \
  "build_output/Osaurus-${VERSION}.dmg" \
  "build_output/osaurus.app" || true

if [ ! -f "build_output/Osaurus-${VERSION}.dmg" ]; then
  echo "create-dmg failed, using basic DMG creation"
  hdiutil create -volname "Osaurus" \
    -srcfolder "build_output/osaurus.app" \
    -ov -format UDZO \
    "build_output/Osaurus-${VERSION}.dmg"
fi

codesign --force --sign "Developer ID Application: ${DEVELOPER_ID_NAME}" \
  "build_output/Osaurus-${VERSION}.dmg"

cp "build_output/Osaurus-${VERSION}.dmg" "build_output/Osaurus.dmg"


