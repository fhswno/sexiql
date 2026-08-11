#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
echo "Generated SexiQL.xcodeproj"
echo "Next: Scripts/build.sh, or open the project in Xcode."
