#!/bin/zsh
# Builds a Release copy of MouseForge and packages it as a DMG you can keep
# and install from: build/MouseForge-<version>.dmg
#
# Signed with the same Apple Development certificate as Xcode's debug
# builds, so macOS keeps the permissions you already granted. Not
# notarized (that needs a paid Developer ID, see docs/SIGNING.md), so it is
# meant for this Mac, not for sharing.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build/release
rm -rf "$BUILD"
xcodebuild -project MouseForge.xcodeproj -scheme MouseForge -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD/derived" -allowProvisioningUpdates build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

APP="$BUILD/derived/Build/Products/Release/MouseForge.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="build/MouseForge-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "MouseForge" -srcfolder "$STAGE" -ov -format UDZO "$DMG" 2>&1 | grep -v deprecated || true
echo "Created $DMG"
