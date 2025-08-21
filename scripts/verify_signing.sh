#!/usr/bin/env bash
set -euo pipefail

echo "Verifying ARM64 app (default)..."
codesign -vvv --deep --strict "build_output/osaurus.app"

echo "Checking Sparkle framework (ARM64)..."
if [ -f "build_output/osaurus.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]; then
  codesign -d --entitlements - "build_output/osaurus.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" 2>&1 | grep -q "<dict/>" && echo "✅ Sparkle has no entitlements" || echo "⚠️ Sparkle might have entitlements"
else
  echo "ℹ️ Sparkle.framework not found in app bundle (skipping check)"
fi


