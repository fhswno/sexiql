#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  printf 'Usage: %s [--notarize]\n' "$0"
  printf '\nBuilds a versioned zip. Notarization requires --notarize and a\n'
  printf 'Developer ID identity plus a notarytool keychain profile.\n'
}

NOTARIZE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notarize)
      NOTARIZE=1
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

SEXIQL_SIGN_IDENTITY="$SIGN_IDENTITY" Scripts/build.sh
APP="$PWD/build/SexiQL.app"
codesign --verify --strict "$APP"

RELEASE_DIR="$PWD/build/releases/$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
ZIP="$RELEASE_DIR/SexiQL-$VERSION.zip"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [ "$NOTARIZE" -eq 1 ]; then
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    rm -f "$ZIP"
    printf 'error: notarization failed; artifact removed\n' >&2
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
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  if ! Scripts/release_preflight.sh --release; then
    rm -f "$ZIP"
    printf 'error: release preflight failed; artifact removed\n' >&2
    exit 1
  fi
else
  printf 'Notarization skipped. Use --notarize only for an explicitly authorized network operation.\n'
fi

echo ">> Generating appcast (EdDSA-signed)"
VENDOR_DIR="$PWD/Vendor"
APPCAST_URL_PREFIX="${APPCAST_URL_PREFIX:-https://github.com/fhswno/sexiql/releases/download/v$VERSION/}"
APPCAST_STAGE="$PWD/build/appcast"
rm -rf "$APPCAST_STAGE"
mkdir -p "$APPCAST_STAGE"
cp "$ZIP" "$APPCAST_STAGE/"

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

CHECKSUM="$RELEASE_DIR/SexiQL-$VERSION.zip.sha256"
shasum -a 256 "$ZIP" | awk -v name="$(basename "$ZIP")" '{print $1 "  " name}' > "$CHECKSUM"
printf 'Created: %s\n' "$ZIP"
printf 'Appcast: %s\n' "$RELEASE_DIR/appcast.xml"
printf 'SHA-256: %s\n' "$CHECKSUM"
