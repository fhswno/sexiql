#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT="$PWD/build/grid_visual_bench"
MOD="$OUT/modules"

rm -rf "$OUT"
mkdir -p "$OUT" "$MOD"

echo ">> SQLDrivers"
drivers=()
while IFS= read -r f; do drivers+=("$PWD/$f"); done < <(find Packages/SQLDrivers/Sources -name '*.swift' | sort)
echo ">> SQLCore"
core=()
while IFS= read -r f; do core+=("$PWD/$f"); done < <(find Packages/SQLCore/Sources -name '*.swift' | sort)
(
  cd "$OUT" && swiftc -swift-version 6 -c -parse-as-library \
    -module-name SQLCore \
    -emit-module -emit-module-path "$MOD/SQLCore.swiftmodule" \
    -sdk "$SDK" -target "$TARGET" \
    "${core[@]}"
)

echo ">> SQLTunnel"
tunnel=()
while IFS= read -r f; do tunnel+=("$PWD/$f"); done < <(find Packages/SQLTunnel/Sources -name '*.swift' | sort)
(
  cd "$OUT" && swiftc -swift-version 6 -c -parse-as-library \
    -module-name SQLTunnel \
    -emit-module -emit-module-path "$MOD/SQLTunnel.swiftmodule" \
    -I "$MOD" -sdk "$SDK" -target "$TARGET" \
    "${tunnel[@]}"
)

echo ">> SQLDrivers"
(
  cd "$OUT" && swiftc -swift-version 6 -c -parse-as-library \
    -module-name SQLDrivers \
    -emit-module -emit-module-path "$MOD/SQLDrivers.swiftmodule" \
    -I "$MOD" -sdk "$SDK" -target "$TARGET" \
    "${drivers[@]}"
)

echo ">> SQLGrid"
grid=()
while IFS= read -r f; do grid+=("$PWD/$f"); done < <(find Packages/SQLGrid/Sources -name '*.swift' | sort)
(
  cd "$OUT" && swiftc -swift-version 6 -c -parse-as-library \
    -module-name SQLGrid \
    -emit-module -emit-module-path "$MOD/SQLGrid.swiftmodule" \
    -I "$MOD" -sdk "$SDK" -target "$TARGET" \
    "${grid[@]}"
)

echo ">> grid_visual_bench"
swiftc -swift-version 6 -parse-as-library \
  -sdk "$SDK" -target "$TARGET" \
  -I "$MOD" \
  -o "$OUT/grid_visual_bench" \
  Scripts/grid_visual_bench.swift \
  "$OUT"/*.o

"$OUT/grid_visual_bench"
