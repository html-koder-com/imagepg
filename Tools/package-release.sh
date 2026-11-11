#!/bin/bash
# Builds a universal app and zips it for a GitHub release: dist/ImagePG-<version>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
UNIVERSAL=1 "$ROOT/build-app.sh"
ZIP="$ROOT/dist/ImagePG-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/ImagePG.app" "$ZIP"
shasum -a 256 "$ZIP"
echo "Release archive: $ZIP"
