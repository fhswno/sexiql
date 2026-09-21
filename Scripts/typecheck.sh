#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
OUT=".typecheck"
STRICT="${SEXIQL_TYPECHECK_STRICT:-0}"

rm -rf "$OUT"
mkdir -p "$OUT"

LOG="$OUT/typecheck.log"
: > "$LOG"

fail() {
  cat "$LOG" >&2
  echo "typecheck failed" >&2
  exit 1
}

run_tc() {
  echo ">> $1"
  shift
  if ! swiftc "$@" >>"$LOG" 2>&1; then
    fail
  fi
}

run_tc "XCTest runtime" \
  -typecheck -swift-version 6 -parse-as-library \
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
  run_tc "$pkg sources" \
    -typecheck -swift-version 6 -parse-as-library $sources \
    -module-name "$pkg" \
    -emit-module -emit-module-path "$OUT/$pkg.swiftmodule" \
    -enable-testing \
    -I "$OUT" -sdk "$SDK" -target "$TARGET"

  if [ -d "Packages/$pkg/Tests" ]; then
    tests=$(find "Packages/$pkg/Tests" -name '*.swift' | sort)
    if [ -n "$tests" ]; then
      run_tc "$pkg tests" \
        -typecheck -swift-version 6 $tests \
        -enable-testing \
        -I "$OUT" -sdk "$SDK" -target "$TARGET"
    fi
  fi
done

app_sources=$(find App -name '*.swift' | sort)
echo ">> App target"
swiftc -typecheck -swift-version 6 -parse-as-library $app_sources \
  -I "$OUT" -F "$PWD/Vendor" -sdk "$SDK" -target "$TARGET"

if [ "$STRICT" = "1" ] && grep -q "warning:" "$LOG"; then
  grep "warning:" "$LOG" >&2
  echo "typecheck strict: warnings found (SEXIQL_TYPECHECK_STRICT=1)" >&2
  exit 1
fi

echo "All packages and the app target typecheck clean."
