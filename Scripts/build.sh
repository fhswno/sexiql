#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
APP="$PWD/build/SexiQL.app"
OBJ="$PWD/build/obj"
MODULES="$PWD/build/modules"

rm -rf "$APP" "$OBJ" "$MODULES"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OBJ" "$MODULES"

PACKAGES=(SQLCore SQLTunnel SQLDrivers SQLEditor SQLGrid SQLExplainer SQLImportExport SQLUI)

for pkg in "${PACKAGES[@]}"; do
  src_dir="Packages/$pkg/Sources"
  if [ ! -d "$src_dir" ]; then
    continue
  fi
  sources=()
  while IFS= read -r f; do sources+=("$PWD/$f"); done < <(find "$src_dir" -name '*.swift' | sort)
  echo ">> module $pkg"
  ( cd "$OBJ" && swiftc -swift-version 6 -c -parse-as-library \
      -module-name "$pkg" \
      -emit-module -emit-module-path "$MODULES/$pkg.swiftmodule" \
      -I "$MODULES" -sdk "$SDK" -target "$TARGET" \
      "${sources[@]}" )
done

echo ">> App target"
app_sources=()
while IFS= read -r f; do app_sources+=("$PWD/$f"); done < <(find App -maxdepth 1 -name '*.swift' | sort)
( cd "$OBJ" && swiftc -swift-version 6 -c -parse-as-library \
    -module-name SexiQL \
    -I "$MODULES" -sdk "$SDK" -target "$TARGET" \
    "${app_sources[@]}" )

echo ">> Linking"
swiftc -sdk "$SDK" -target "$TARGET" \
  "$OBJ"/*.o \
  -o "$APP/Contents/MacOS/SexiQL"

echo ">> Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>SexiQL</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.sexiql.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>SexiQL</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Dave Ohayon. All rights reserved.</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo ">> App icon"
swift Scripts/generate_icon.swift >/dev/null
ICON_DARK="App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
ICON_LIGHT="App/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png"
cp "$ICON_DARK" "$APP/Contents/Resources/AppIcon-dark.png"
cp "$ICON_LIGHT" "$APP/Contents/Resources/AppIcon-light.png"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in \
  "16 16 icon_16x16.png" \
  "32 32 icon_16x16@2x.png" \
  "32 32 icon_32x32.png" \
  "64 64 icon_32x32@2x.png" \
  "128 128 icon_128x128.png" \
  "256 256 icon_128x128@2x.png" \
  "256 256 icon_256x256.png" \
  "512 512 icon_256x256@2x.png" \
  "512 512 icon_512x512.png" \
  "1024 1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$2" "$ICON_DARK" --out "$ICONSET/$3" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo ">> Signing (ad-hoc)"
codesign --force --sign - --entitlements App/SexiQL.entitlements "$APP"

echo "Built: $APP"
echo "Run:   open build/SexiQL.app"
