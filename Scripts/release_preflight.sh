#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SexiQL.app"
if [ ! -d "$APP" ]; then
  echo "error: $APP is missing; run Scripts/build.sh first"
  exit 1
fi

codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

echo "Bundle signature: valid"
echo "Bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
echo "Architecture: $(file -b "$APP/Contents/MacOS/SexiQL")"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "Developer ID Application identity: available"
else
  echo "Developer ID Application identity: unavailable (notarization is not ready)"
fi

if xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool: available"
else
  echo "notarytool: unavailable"
fi

echo "No signing, upload, notarization, or network operation was performed."
