#!/bin/sh
# Builds the app and packages it as build/NotchHider.dmg (drag-to-Applications installer).
set -e
cd "$(dirname "$0")/.."

./build.sh

STAGING=build/dmg
DMG=build/NotchHider.dmg
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/NotchHider.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname NotchHider -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
echo "Built $DMG"
