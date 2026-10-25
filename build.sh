#!/bin/bash
# Builds Brim.app (ad-hoc signed) into ./build. Usage: ./build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Brim.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Brim" "$APP/Contents/MacOS/Brim"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundles are looked up in Contents/Resources. None today, but keep the loop so
# adding a resource later does not silently break the app bundle.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --deep --sign - "$APP"
echo "Built $APP"
