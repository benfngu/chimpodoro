#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
  --help|-h)
    echo "usage: ./package.sh"
    echo "builds Chimpodoro and creates a local ZIP and SHA-256 checksum in build/release"
    exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then echo "usage: ./package.sh" >&2; exit 2; fi

./build.sh
app="$PWD/build/Chimpodoro.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(uname -m)"
release="$PWD/build/release"
mkdir -p "$release"
stage="$(mktemp -d "$release/.chimpodoro-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
filename="Chimpodoro-${version}-macOS-${architecture}.zip"

ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$filename"
unzip -tq "$stage/$filename"
mv "$stage/$filename" "$release/$filename"
cd "$release"
shasum -a 256 "$filename" > "$filename.sha256"
echo "packaged: $release/$filename"
du -h "$filename"
