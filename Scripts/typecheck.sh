#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT=".typecheck"

rm -rf "$OUT"
mkdir -p "$OUT"

swiftc -typecheck -swift-version 6 -parse-as-library \
  -module-name XCTest \
  -emit-module -emit-module-path "$OUT/XCTest.swiftmodule" \
  -sdk "$SDK" -target "$TARGET" \
  Scripts/TestRuntime.swift

PACKAGES=(SQLCore SQLTunnel SQLDrivers SQLEditor SQLGrid SQLExplainer SQLImportExport SQLUI)

for pkg in "${PACKAGES[@]}"; do
  src_dir="Packages/$pkg/Sources"
  if [ ! -d "$src_dir" ]; then
    echo "skip $pkg (no Sources)"
    continue
  fi
  sources=$(find "$src_dir" -name '*.swift' | sort)
  echo ">> $pkg sources"
  swiftc -typecheck -swift-version 6 -parse-as-library $sources \
    -module-name "$pkg" \
    -emit-module -emit-module-path "$OUT/$pkg.swiftmodule" \
    -enable-testing \
    -I "$OUT" -sdk "$SDK" -target "$TARGET"

  if [ -d "Packages/$pkg/Tests" ]; then
    tests=$(find "Packages/$pkg/Tests" -name '*.swift' | sort)
    if [ -n "$tests" ]; then
      echo ">> $pkg tests"
      swiftc -typecheck -swift-version 6 $tests \
        -enable-testing \
        -I "$OUT" -sdk "$SDK" -target "$TARGET"
    fi
  fi
done

app_sources=$(find App -name '*.swift' | sort)
echo ">> App target"
swiftc -typecheck -swift-version 6 -parse-as-library $app_sources \
  -I "$OUT" -sdk "$SDK" -target "$TARGET"

echo "All packages and the app target typecheck clean."
