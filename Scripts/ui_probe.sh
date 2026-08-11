#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT="$PWD/build/uiprobe"

if [ ! -d build/testmods ]; then
  echo "error: build/testmods missing — run Scripts/test.sh first"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

ROOT="$PWD"
APP_SOURCES=$(find App -maxdepth 1 -name '*.swift' ! -name 'SexiQLApp.swift' | sort)
( cd "$OUT" && swiftc -c -parse-as-library -enable-testing -swift-version 6 \
    -module-name SexiQLView \
    -emit-module -emit-module-path "$OUT/SexiQLView.swiftmodule" \
    -I "$ROOT/build/testmods" -sdk "$SDK" -target "$TARGET" \
    $(printf '%s ' "$ROOT"/App/{AppDelegate,ConnectionEditorView,ContentView,EditorView,ExplainView,ImportSheet,SparkleUpdater,WorkspaceModel}.swift) )

swiftc -parse-as-library -swift-version 6 -module-name UIProbe \
  -I "$OUT" -I build/testmods -sdk "$SDK" -target "$TARGET" \
  Scripts/ui_probe.swift \
  "$OUT"/*.o build/testmods/*.o \
  -o "$OUT/ui_probe"

"$OUT/ui_probe"
