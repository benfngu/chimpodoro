#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p Assets build/ModuleCache
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
iconset="$temporary/Chimpodoro.iconset"
xcrun swiftc -swift-version 5 -O -gnone -framework AppKit \
  -module-cache-path "$PWD/build/ModuleCache" \
  Sources/ChimpMark.swift Scripts/main.swift -o "$temporary/make-icon"
"$temporary/make-icon" "$iconset" "$PWD/Assets/Chimpodoro.png"
iconutil -c icns "$iconset" -o Assets/Chimpodoro.icns
echo "created: Assets/Chimpodoro.png and Assets/Chimpodoro.icns"
