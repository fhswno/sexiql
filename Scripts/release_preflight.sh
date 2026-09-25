#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SexiQL.app"
REQUIRE_RELEASE=0
if [ "${1:-}" = "--release" ]; then
  REQUIRE_RELEASE=1
elif [ "${1:-}" != "" ]; then
  echo "error: unknown argument: $1" >&2
  echo "Usage: $0 [--release]" >&2
  exit 2
fi

if [ ! -d "$APP" ]; then
  echo "error: $APP is missing; run Scripts/build.sh first"
  exit 1
fi

codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

VERSION_FILE="$PWD/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  echo "error: missing VERSION file" >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
PROJECT_VERSION="$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml 2>/dev/null || true)"
if [ "$REQUIRE_RELEASE" -eq 1 ] && [ -n "$PROJECT_VERSION" ] && [ "$PROJECT_VERSION" != "$VERSION" ]; then
  echo "error: project.yml MARKETING_VERSION $PROJECT_VERSION does not match VERSION $VERSION" >&2
  exit 1
fi
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
if [ "$SHORT_VERSION" != "$VERSION" ]; then
  echo "error: bundle version $SHORT_VERSION does not match VERSION $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: invalid bundle build number: $BUILD_VERSION" >&2
  exit 1
fi

SIGNING_INFO="$(codesign --display --verbose=4 "$APP" 2>&1)"
if echo "$SIGNING_INFO" | grep -q "flags=0x[0-9a-f]*(.*runtime)"; then
  echo "Hardened runtime: enabled"
else
  echo "Hardened runtime: unavailable"
  if [ "$REQUIRE_RELEASE" -eq 1 ]; then
    echo "error: a release build must enable the hardened runtime" >&2
    exit 1
  fi
fi

if [[ "$SIGNING_INFO" == *"Authority=Developer ID Application:"* ]]; then
  echo "Signing identity: Developer ID Application"
  HAS_DEVELOPER_ID=1
else
  echo "Signing identity: ad-hoc or other"
  HAS_DEVELOPER_ID=0
fi

if [ "$REQUIRE_RELEASE" -eq 1 ] && [ "$HAS_DEVELOPER_ID" -ne 1 ]; then
  echo "error: --release requires a Developer ID Application signature" >&2
  exit 1
fi

echo "Bundle signature: valid"
echo "Bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
echo "Architecture: $(file -b "$APP/Contents/MacOS/SexiQL")"
echo "Version: $SHORT_VERSION ($BUILD_VERSION)"

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

if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "Notarization ticket: stapled"
elif [ "$REQUIRE_RELEASE" -eq 1 ]; then
  echo "error: --release requires a stapled notarization ticket" >&2
  exit 1
else
  echo "Notarization ticket: not stapled"
fi

DMG="build/releases/$VERSION/SexiQL-$VERSION.dmg"
if [ -f "$DMG" ]; then
  echo "DMG: $DMG"
  if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "DMG notarization ticket: stapled"
    MOUNT="$(mktemp -d)/dmg"
    if ! hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -readonly -quiet; then
      echo "error: failed to mount $DMG for inspection" >&2
      exit 1
    fi
    if spctl -a -vv "$MOUNT/SexiQL.app" 2>&1 | grep -q "accepted"; then
      echo "DMG Gatekeeper assessment: accepted"
    else
      spctl -a -vv "$MOUNT/SexiQL.app" >&2 || true
      hdiutil detach "$MOUNT" -quiet || true
      echo "error: app inside DMG failed Gatekeeper assessment" >&2
      exit 1
    fi
    hdiutil detach "$MOUNT" -quiet
  elif [ "$REQUIRE_RELEASE" -eq 1 ]; then
    echo "error: --release requires a stapled DMG notarization ticket" >&2
    exit 1
  else
    echo "DMG notarization ticket: not stapled"
  fi
elif [ "$REQUIRE_RELEASE" -eq 1 ]; then
  echo "error: --release requires a built DMG at $DMG" >&2
  exit 1
fi

if [ "$REQUIRE_RELEASE" -eq 0 ]; then
  echo "No signing, upload, notarization, or network operation was performed."
fi
