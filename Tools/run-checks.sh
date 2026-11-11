#!/bin/bash
# Compiles every Tests/*Check.swift together with the app sources and runs it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/.build/checks"
CACHE="$ROOT/.build/module-cache"
mkdir -p "$OUT" "$CACHE"
SOURCES=()
for FILE in Sources/ImagePG/*.swift; do
  [[ "$(basename "$FILE")" == "main.swift" ]] || SOURCES+=("$FILE")
done
for CHECK in Tests/*.swift; do
  NAME="$(basename "$CHECK" .swift)"
  swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$CACHE" \
    -parse-as-library "${SOURCES[@]}" "$CHECK" -o "$OUT/$NAME"
  "$OUT/$NAME" > /dev/null
  echo "✓ $NAME"
done
