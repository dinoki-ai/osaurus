#!/usr/bin/env bash
set -euo pipefail

: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required}"

echo "Building ARM64 version (default)..."

xcodebuild -project osaurus.xcodeproj \
  -scheme osaurus \
  -configuration Release \
  -derivedDataPath build \
  ARCHS=arm64 \
  VALID_ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY="Developer ID Application: ${DEVELOPER_ID_NAME}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Manual \
  clean archive -archivePath build/osaurus.xcarchive

cat > ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath build/osaurus.xcarchive \
  -exportPath build_output \
  -exportOptionsPlist ExportOptions.plist


