#!/usr/bin/env bash
set -euo pipefail

: "${MACOS_CERTIFICATE_BASE64:?MACOS_CERTIFICATE_BASE64 is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is required}"
: "${KEYCHAIN_PASSWORD:?KEYCHAIN_PASSWORD is required}"

CERTIFICATE_PATH="$RUNNER_TEMP/build_certificate.p12"
KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"

echo -n "$MACOS_CERTIFICATE_BASE64" | base64 --decode -o "$CERTIFICATE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Ensure the temporary keychain is the default and in the search list
security default-keychain -d user -s "$KEYCHAIN_PATH"

security import "$CERTIFICATE_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH"

security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"


