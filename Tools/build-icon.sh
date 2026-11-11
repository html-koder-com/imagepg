#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/Resources/ImagePG.iconset"
SOURCE="$ROOT/Resources/ImagePG.png"
BUILD="$ROOT/.build/icon"

mkdir -p "$BUILD/module-cache"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$BUILD/module-cache" \
  "$ROOT/Tools/create-icon.swift" -o "$BUILD/create-icon"
"$BUILD/create-icon" "$SOURCE"
mkdir -p "$ICONSET"
for POINTS in 16 32 128 256 512; do
  sips -z "$POINTS" "$POINTS" "$SOURCE" --out "$ICONSET/icon_${POINTS}x${POINTS}.png" >/dev/null
  PIXELS=$((POINTS * 2))
  sips -z "$PIXELS" "$PIXELS" "$SOURCE" --out "$ICONSET/icon_${POINTS}x${POINTS}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$ROOT/Resources/ImagePG.icns" <<'PY'
from pathlib import Path
import struct
import sys

iconset, output = map(Path, sys.argv[1:])
parts = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]
chunks = []
for kind, name in parts:
    png = (iconset / name).read_bytes()
    chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
PY
rm -rf "$ICONSET"
