#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/ImagePG.app"
MACOS="$APP/Contents/MacOS"
CACHE="$ROOT/.build/module-cache"
ARCH="$(uname -m)"

mkdir -p "$MACOS" "$CACHE"
swiftc -O -gnone -swift-version 5 -target "$ARCH-apple-macos14.0" \
  -module-cache-path "$CACHE" \
  "$ROOT"/Sources/ImagePG/*.swift \
  -o "$MACOS/ImagePG"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/ImagePG.icns" "$APP/Contents/Resources/ImagePG.icns"
cp "$ROOT/Resources/ImagePG.png" "$APP/Contents/Resources/ImagePG.png"
codesign --force --sign - "$APP"
touch "$APP"
echo "Hotovo: $APP"
