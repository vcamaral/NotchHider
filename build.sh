#!/bin/sh
# Builds NotchHider.app into ./build
set -e
cd "$(dirname "$0")"

APP=build/NotchHider.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/NotchHider"
codesign --force --sign - "$APP"
echo "Built $APP"
