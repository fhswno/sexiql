#!/usr/bin/env bash
# Downloads and vendors the Sparkle framework (pinned version, checksum-verified).
# Idempotent: exits fast when the framework is already installed.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

VENDOR="$PWD/Vendor"
FRAMEWORK="$VENDOR/Sparkle.framework"
TOOLS="$VENDOR/bin"

if [ -d "$FRAMEWORK" ] && [ -x "$TOOLS/generate_keys" ]; then
  echo "Sparkle $SPARKLE_VERSION already installed"
  exit 0
fi

mkdir -p "$VENDOR/tmp"
ARCHIVE="$VENDOR/tmp/Sparkle-$SPARKLE_VERSION.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

echo ">> Downloading Sparkle $SPARKLE_VERSION"
curl -sSL -o "$ARCHIVE" "$URL"

echo ">> Verifying SHA-256"
echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c -

echo ">> Extracting"
tar -xJf "$ARCHIVE" -C "$VENDOR/tmp"

rm -rf "$FRAMEWORK"
mv "$VENDOR/tmp/Sparkle.framework" "$FRAMEWORK"
rm -rf "$TOOLS"
mkdir -p "$TOOLS"
cp -R "$VENDOR/tmp/bin/" "$TOOLS/"
chmod +x "$TOOLS/"*

rm -rf "$VENDOR/tmp"
echo "Sparkle $SPARKLE_VERSION installed: $FRAMEWORK"
