#!/bin/sh
# Builds NotchHider.app into ./build
set -e
cd "$(dirname "$0")"

APP=build/NotchHider.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"

# App icon: render the master PNG, then every size iconutil expects.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Universal binary (Apple silicon + Intel).
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13.0 Sources/*.swift -o build/NotchHider-$arch
done
lipo -create build/NotchHider-arm64 build/NotchHider-x86_64 -output "$APP/Contents/MacOS/NotchHider"
codesign --force --sign - "$APP"
echo "Built $APP"
