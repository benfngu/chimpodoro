#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

install_app=false
open_app=false
for argument in "$@"; do
  case "$argument" in
    --install) install_app=true ;;
    --open) open_app=true ;;
    --help|-h)
      echo "usage: ./build.sh [--install] [--open]"
      echo "builds a native release app; --install copies it to ~/Applications"
      exit 0 ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

app="$PWD/build/Chimpodoro.app"
destination="$HOME/Applications/Chimpodoro.app"
build_stage=""
install_stage=""
cleanup_stage() {
  local stage="$1"
  local target="$2"
  if [[ -z "$stage" || ! -d "$stage" ]]; then return; fi
  # Recover the old app if replacement was interrupted between the two renames.
  if [[ -e "$stage/previous.app" && ! -e "$target" ]]; then
    if ! mv "$stage/previous.app" "$target"; then
      echo "previous app preserved at: $stage/previous.app" >&2
      return
    fi
  fi
  rm -rf "$stage"
}
cleanup() {
  cleanup_stage "$build_stage" "$PWD/build/Chimpodoro.app"
  cleanup_stage "$install_stage" "$destination"
}
trap cleanup EXIT

# Opening an existing process does not switch it to the newly built executable.
require_stopped() {
  local executable="$1/Contents/MacOS/Chimpodoro"
  if ps -axww -o comm= | awk -v executable="$executable" \
      '$0 == executable { found = 1 } END { exit !found }'; then
    echo "quit Chimpodoro from its menu bar before replacing $1" >&2
    exit 1
  fi
}

# Keep the previous bundle until a complete, signed replacement is ready.
replace_bundle() {
  local prepared="$1"
  local target="$2"
  local backup="$3"
  require_stopped "$target"
  if [[ -e "$target" ]]; then mv "$target" "$backup"; fi
  if ! mv "$prepared" "$target"; then
    if [[ -e "$backup" ]]; then mv "$backup" "$target"; fi
    echo "could not replace $target" >&2
    exit 1
  fi
}

require_stopped "$app"
if "$install_app"; then require_stopped "$destination"; fi

sdk="$(xcrun --sdk macosx --show-sdk-path)"
architecture="$(uname -m)"
mkdir -p build/ModuleCache
build_stage="$(mktemp -d "$PWD/build/.chimpodoro-build.XXXXXX")"
prepared="$build_stage/Chimpodoro.app"
mkdir -p "$prepared/Contents/MacOS" "$prepared/Contents/Resources"

xcrun swiftc -swift-version 5 \
  -target "${architecture}-apple-macosx14.0" -sdk "$sdk" \
  -module-name Chimpodoro -module-cache-path "$PWD/build/ModuleCache" \
  -O -whole-module-optimization -gnone -Xlinker -dead_strip \
  -framework AppKit -framework Security -framework UserNotifications -framework ServiceManagement \
  Sources/*.swift -o "$prepared/Contents/MacOS/Chimpodoro"

cp Info.plist "$prepared/Contents/Info.plist"
cp Assets/Chimpodoro.icns "$prepared/Contents/Resources/Chimpodoro.icns"
plutil -lint "$prepared/Contents/Info.plist"
codesign --force --sign - --identifier local.ben.chimpodoro --timestamp=none "$prepared"
codesign --verify --deep --strict "$prepared"
replace_bundle "$prepared" "$app" "$build_stage/previous.app"
echo "built: $app"
du -sh "$app"

if "$install_app"; then
  mkdir -p "$HOME/Applications"
  install_stage="$(mktemp -d "$HOME/Applications/.chimpodoro-install.XXXXXX")"
  ditto "$app" "$install_stage/Chimpodoro.app"
  codesign --verify --deep --strict "$install_stage/Chimpodoro.app"
  replace_bundle "$install_stage/Chimpodoro.app" "$destination" "$install_stage/previous.app"
  app="$destination"
  echo "installed: $app"
fi
if "$open_app"; then open "$app"; fi
