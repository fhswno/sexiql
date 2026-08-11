#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT="$PWD/build/tab_switch_bench"
MOD="$OUT/modules"

rm -rf "$OUT"
mkdir -p "$OUT" "$MOD"

echo ">> SQLEditor module"
sources=()
while IFS= read -r f; do sources+=("$PWD/$f"); done < <(find Packages/SQLEditor/Sources/SQLEditor -name '*.swift' | sort)
(
  cd "$OUT"
  swiftc -swift-version 6 -c -parse-as-library \
    -module-name SQLEditor \
    -emit-module -emit-module-path "$MOD/SQLEditor.swiftmodule" \
    -sdk "$SDK" -target "$TARGET" \
    "${sources[@]}"
)

echo ">> tab_switch_bench"
swiftc -swift-version 6 -parse-as-library \
  -sdk "$SDK" -target "$TARGET" \
  -I "$MOD" \
  -o "$OUT/tab_switch_bench" \
  App/TabEditorHostView.swift \
  Scripts/tab_switch_bench.swift \
  "$OUT"/*.o

"$OUT/tab_switch_bench"
