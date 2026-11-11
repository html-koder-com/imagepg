#!/bin/bash
# Builds dist/ImagePG.app. Set UNIVERSAL=1 for an Apple Silicon + Intel binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/ImagePG.app"
MACOS="$APP/Contents/MacOS"
CACHE="$ROOT/.build/module-cache"

mkdir -p "$MACOS" "$CACHE"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
  OUT="$ROOT/.build/ImagePG-$ARCH"
  swiftc -O -gnone -swift-version 5 -target "$ARCH-apple-macos14.0" \
    -module-cache-path "$CACHE" \
    "$ROOT"/Sources/ImagePG/*.swift \
    -o "$OUT"
  BINARIES+=("$OUT")
done
lipo -create "${BINARIES[@]}" -output "$MACOS/ImagePG"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/ImagePG.icns" "$APP/Contents/Resources/ImagePG.icns"
cp "$ROOT/Resources/ImagePG.png" "$APP/Contents/Resources/ImagePG.png"
rm -rf "$APP/Contents/Resources/"*.lproj
cp -R "$ROOT/Resources/"*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
touch "$APP"
echo "Done: $APP ($(lipo -archs "$MACOS/ImagePG"))"
