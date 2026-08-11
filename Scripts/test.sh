#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
TESTMODS="$PWD/build/testmods"
TESTBIN="$PWD/build/test"
XCTEST="$PWD/build/xctest"

rm -rf "$TESTMODS" "$TESTBIN" "$XCTEST"
mkdir -p "$TESTMODS" "$TESTBIN" "$XCTEST"

echo ">> XCTest runtime"
swiftc -swift-version 6 -c -parse-as-library \
  -module-name XCTest \
  -emit-module -emit-module-path "$XCTEST/XCTest.swiftmodule" \
  -sdk "$SDK" -target "$TARGET" \
  -o "$XCTEST/XCTest.o" \
  Scripts/TestRuntime.swift

PACKAGES=(SQLCore SQLTunnel SQLDrivers SQLEditor SQLGrid SQLExplainer SQLImportExport SQLUI)

for pkg in "${PACKAGES[@]}"; do
  src_dir="Packages/$pkg/Sources"
  if [ ! -d "$src_dir" ]; then
    continue
  fi
  sources=()
  while IFS= read -r f; do sources+=("$PWD/$f"); done < <(find "$src_dir" -name '*.swift' | sort)
  echo ">> module $pkg"
  ( cd "$TESTMODS" && swiftc -swift-version 6 -c -parse-as-library \
      -module-name "$pkg" \
      -emit-module -emit-module-path "$TESTMODS/$pkg.swiftmodule" \
      -enable-testing \
      -I "$TESTMODS" -I "$XCTEST" -sdk "$SDK" -target "$TARGET" \
      "${sources[@]}" )
done

total_failures=0

for pkg in "${PACKAGES[@]}"; do
  test_dir="Packages/$pkg/Tests"
  if [ ! -d "$test_dir" ]; then
    continue
  fi

  parsed=$(awk '
    /^[[:space:]]*final class [A-Za-z0-9_]+: XCTestCase/ {
      match($0, /final class [A-Za-z0-9_]+: XCTestCase/)
      s = substr($0, RSTART, RLENGTH)
      gsub(/final class |: XCTestCase/, "", s)
      cls = s
      next
    }
    cls != "" && /^[[:space:]]*func test[A-Za-z0-9_]*[[:space:]]*\(/ {
      if (index($0, "{") == 0) {
        print "WRAPPED-DECLARATION: " $0 > "/dev/stderr"
        exit 1
      }
      name = $0
      sub(/^[[:space:]]*func /, "", name)
      sub(/\(.*$/, "", name)
      is_async = (match($0, /[[:space:]]async([[:space:]]|$)/) > 0) ? 1 : 0
      is_throws = (match($0, /[[:space:]]throws([[:space:]]|$)/) > 0) ? 1 : 0
      print cls "\t" name "\t" is_async "\t" is_throws
    }
  ' $(find "$test_dir" -name '*.swift' | sort))

  runner="$TESTBIN/$pkg.runner.swift"
  {
    echo "import XCTest"
    echo ""
    echo "@main"
    echo "struct TestRunner {"
    echo "    @MainActor"
    echo "    static func main() async {"
    echo "        var failures = 0"
    current=""
    while IFS=$'\t' read -r cls name is_async is_throws; do
      if [ "$cls" != "$current" ]; then
        if [ -n "$current" ]; then
          echo "        ])"
        fi
        current="$cls"
        echo "        failures += await runSuite($cls(), tests: ["
      fi
      if [ "$is_async" = "1" ] && [ "$is_throws" = "1" ]; then
        call="try await t.$name()"
      elif [ "$is_async" = "1" ]; then
        call="await t.$name()"
      elif [ "$is_throws" = "1" ]; then
        call="try t.$name()"
      else
        call="t.$name()"
      fi
      echo "            { t in $call },"
    done <<< "$parsed"
    if [ -n "$current" ]; then
      echo "        ])"
    fi
    echo "        if failures > 0 {"
    echo "            print(\"\\(failures) failure(s)\")"
    echo "            exit(1)"
    echo "        }"
    echo "        print(\"All tests passed\")"
    echo "    }"
    echo "}"
  } > "$runner"

  echo ">> tests $pkg"
  swiftc -swift-version 6 -parse-as-library -enable-testing \
    -module-name "${pkg}Tests" \
    -I "$TESTMODS" -I "$XCTEST" -sdk "$SDK" -target "$TARGET" \
    "$runner" \
    $(find "$test_dir" -name '*.swift' | sort) \
    $(find "$TESTMODS" -name '*.o' | sort) \
    "$XCTEST/XCTest.o" \
    -o "$TESTBIN/$pkg"

  if "$TESTBIN/$pkg"; then
    echo "PASS $pkg"
  else
    echo "FAIL $pkg (see output above)"
    total_failures=$((total_failures + 1))
  fi
done

if [ "$total_failures" -gt 0 ]; then
  echo "$total_failures package(s) failed"
  exit 1
fi
echo "All test packages passed"
