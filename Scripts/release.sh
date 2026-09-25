#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  printf 'Usage: %s [--notarize] [--skip-appcast]\n' "$0"
  printf '\nBuilds a versioned zip and DMG. Notarization requires --notarize and a\n'
  printf 'Developer ID identity plus a notarytool keychain profile.\n'
  printf -- '--skip-appcast omits EdDSA-signed appcast generation (CI, where the\n'
  printf 'signing key never leaves the release machine).\n'
}

NOTARIZE=0
SKIP_APPCAST=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notarize)
      NOTARIZE=1
      ;;
    --skip-appcast)
      SKIP_APPCAST=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

VERSION_FILE="$PWD/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  printf 'error: missing VERSION file\n' >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'error: invalid version in VERSION: %s\n' "$VERSION" >&2
  exit 1
fi

SIGN_IDENTITY="${SEXIQL_SIGN_IDENTITY:-${SEXIQL_DEVELOPER_ID:-}}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="-"
fi
NOTARY_PROFILE="${SEXIQL_NOTARY_PROFILE:-}"

if [ "$NOTARIZE" -eq 1 ]; then
  if [ "$SIGN_IDENTITY" = "-" ]; then
    printf 'error: --notarize requires SEXIQL_SIGN_IDENTITY or SEXIQL_DEVELOPER_ID\n' >&2
    exit 1
  fi
  if [ -z "$NOTARY_PROFILE" ]; then
    printf 'error: --notarize requires SEXIQL_NOTARY_PROFILE\n' >&2
    exit 1
  fi
fi

cleanup_artifacts() {
  rm -f "$ZIP" "$DMG" \
    "$RELEASE_DIR/SexiQL-$VERSION.zip.sha256" \
    "$RELEASE_DIR/SexiQL-$VERSION.dmg.sha256" \
    "$RELEASE_DIR/SexiQL.zip" "$RELEASE_DIR/SexiQL.zip.sha256" \
    "$RELEASE_DIR/SexiQL.dmg" "$RELEASE_DIR/SexiQL.dmg.sha256"
}

SEXIQL_SIGN_IDENTITY="$SIGN_IDENTITY" Scripts/build.sh
APP="$PWD/build/SexiQL.app"
codesign --verify --strict "$APP"

RELEASE_DIR="$PWD/build/releases/$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
ZIP="$RELEASE_DIR/SexiQL-$VERSION.zip"
DMG="$RELEASE_DIR/SexiQL-$VERSION.dmg"

echo ">> Packaging zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [ "$NOTARIZE" -eq 1 ]; then
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    rm -f "$ZIP"
    printf 'error: zip notarization failed; artifact removed\n' >&2
    exit 1
  fi
  if ! xcrun stapler staple "$APP"; then
    rm -f "$ZIP"
    printf 'error: stapling failed; artifact removed\n' >&2
    exit 1
  fi
  if ! xcrun stapler validate "$APP"; then
    rm -f "$ZIP"
    printf 'error: staple validation failed; artifact removed\n' >&2
    exit 1
  fi
  rm -f "$ZIP"
  echo ">> Repackaging stapled app"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
else
  printf 'Notarization skipped. Use --notarize only for an explicitly authorized network operation.\n'
fi

echo ">> Building DMG"
Scripts/install_dmgbuild.sh
"$PWD/build/dmg-venv/bin/dmgbuild" \
  -s Scripts/dmg_settings.py \
  -Dapp="$APP" \
  -Dversion="$VERSION" \
  "SexiQL $VERSION" "$DMG"

if [ "$NOTARIZE" -eq 1 ]; then
  if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
    cleanup_artifacts
    printf 'error: DMG notarization failed; artifacts removed\n' >&2
    exit 1
  fi
  if ! xcrun stapler staple "$DMG"; then
    cleanup_artifacts
    printf 'error: DMG stapling failed; artifacts removed\n' >&2
    exit 1
  fi
  if ! xcrun stapler validate "$DMG"; then
    cleanup_artifacts
    printf 'error: DMG staple validation failed; artifacts removed\n' >&2
    exit 1
  fi
  if ! Scripts/release_preflight.sh --release; then
    cleanup_artifacts
    printf 'error: release preflight failed; artifacts removed\n' >&2
    exit 1
  fi
fi

make_checksum() {
  shasum -a 256 "$1" | awk -v name="$2" '{print $1 "  " name}' > "$RELEASE_DIR/$2.sha256"
}

make_checksum "$ZIP" "SexiQL-$VERSION.zip"
make_checksum "$DMG" "SexiQL-$VERSION.dmg"
cp "$ZIP" "$RELEASE_DIR/SexiQL.zip"
cp "$DMG" "$RELEASE_DIR/SexiQL.dmg"
make_checksum "$RELEASE_DIR/SexiQL.zip" "SexiQL.zip"
make_checksum "$RELEASE_DIR/SexiQL.dmg" "SexiQL.dmg"

printf 'Created: %s\n' "$ZIP"
printf 'Created: %s\n' "$DMG"
printf 'SHA-256: %s\n' "$RELEASE_DIR/SexiQL-$VERSION.zip.sha256"
printf 'SHA-256: %s\n' "$RELEASE_DIR/SexiQL-$VERSION.dmg.sha256"

echo ">> Generating appcast (EdDSA-signed)"
if [ "$SKIP_APPCAST" -eq 1 ]; then
  printf 'Appcast generation skipped (--skip-appcast)\n'
  exit 0
fi

VENDOR_DIR="$PWD/Vendor"
APPCAST_URL_PREFIX="${APPCAST_URL_PREFIX:-https://github.com/fhswno/sexiql/releases/download/v$VERSION/}"
APPCAST_STAGE="$PWD/build/appcast"
rm -rf "$APPCAST_STAGE"
mkdir -p "$APPCAST_STAGE"
cp "$DMG" "$APPCAST_STAGE/"

if ! "$VENDOR_DIR/bin/generate_appcast" \
    --download-url-prefix "$APPCAST_URL_PREFIX" \
    "$APPCAST_STAGE"; then
  rm -rf "$APPCAST_STAGE"
  if [ "$NOTARIZE" -ne 1 ] && [ "${ALLOW_MISSING_APPCAST:-0}" = "1" ]; then
    printf 'Appcast generation skipped (no signing key available)\n'
    exit 0
  fi
  printf 'error: appcast generation failed\n' >&2
  exit 1
fi

mv "$APPCAST_STAGE/appcast.xml" "$RELEASE_DIR/appcast.xml"
printf 'Appcast: %s\n' "$RELEASE_DIR/appcast.xml"
