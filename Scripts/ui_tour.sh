#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT="$PWD/build/uitour"

if [ ! -d build/testmods ]; then
  echo "error: build/testmods missing — run Scripts/test.sh first"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

ROOT="$PWD"
APP_SOURCES=$(find "$ROOT/App" -maxdepth 1 -name '*.swift' ! -name 'SexiQLApp.swift' | sort)
( cd "$OUT" && swiftc -c -parse-as-library -enable-testing -swift-version 6 \
    -module-name SexiQLView \
    -emit-module -emit-module-path "$OUT/SexiQLView.swiftmodule" \
    -I "$ROOT/build/testmods" -F "$ROOT/Vendor" -sdk "$SDK" -target "$TARGET" \
    $(printf '%s ' "$APP_SOURCES") )

swiftc -parse-as-library -swift-version 6 -module-name UITour \
  -I "$OUT" -I build/testmods -F "$ROOT/Vendor" -sdk "$SDK" -target "$TARGET" -framework Sparkle -Xlinker -rpath -Xlinker "$ROOT/Vendor" \
  Scripts/ui_tour.swift \
  "$OUT"/*.o build/testmods/*.o \
  -o "$OUT/ui_tour"

"$OUT/ui_tour"
