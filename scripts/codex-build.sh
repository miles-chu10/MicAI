#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
export PROJECT_ROOT
APP_BUNDLE="$PROJECT_ROOT/dist/MicAI.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
EXECUTABLE_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICON_WORK_DIR="$PROJECT_ROOT/.build/micai-app-icon"
ICONSET_DIR="$ICON_WORK_DIR/MicAI.iconset"
ICON_GENERATOR="$ICON_WORK_DIR/generate-app-icon"
ICON_PATH="$RESOURCES_DIR/MicAI.icns"

# shellcheck source=scripts/codex-swift-env.sh
source "$SCRIPT_DIR/codex-swift-env.sh"

cd "$PROJECT_ROOT"
"$MICAI_SWIFT_BIN" build --configuration release --scratch-path "$MICAI_SWIFT_SCRATCH_PATH"
BIN_DIR="$("$MICAI_SWIFT_BIN" build --configuration release --scratch-path "$MICAI_SWIFT_SCRATCH_PATH" --show-bin-path)"

if [ -e "$APP_BUNDLE" ]; then
  case "$APP_BUNDLE" in
    "$PROJECT_ROOT/dist/MicAI.app")
      find "$APP_BUNDLE" -depth -delete
      ;;
    *)
      echo "Refusing to replace unexpected app path: $APP_BUNDLE" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$EXECUTABLE_DIR" "$RESOURCES_DIR" "$ICON_WORK_DIR"
install -m 755 "$BIN_DIR/MicAI" "$EXECUTABLE_DIR/MicAI"
"$MICAI_SWIFTC_BIN" "$PROJECT_ROOT/scripts/generate-app-icon.swift" \
  -framework AppKit \
  -o "$ICON_GENERATOR"
"$ICON_GENERATOR" "$ICONSET_DIR"
/usr/bin/iconutil --convert icns --output "$ICON_PATH" "$ICONSET_DIR"

/usr/bin/plutil -create xml1 "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleDisplayName -string "MicAI" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleExecutable -string "MicAI" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleIconFile -string "MicAI" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.mileschu.micai" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleName -string "MicAI" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleShortVersionString -string "0.1.0" "$PLIST_PATH"
/usr/bin/plutil -insert CFBundleVersion -string "1" "$PLIST_PATH"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "14.0" "$PLIST_PATH"
/usr/bin/plutil -insert LSUIElement -bool true "$PLIST_PATH"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$PLIST_PATH"
/usr/bin/plutil -insert NSMicrophoneUsageDescription \
  -string "MicAI records audio only while you invoke dictation or a voice command." \
  "$PLIST_PATH"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/bin/plutil -extract "$key" raw -o - "$PLIST_PATH")"
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected $key in $PLIST_PATH: $actual" >&2
    exit 1
  fi
}

/usr/bin/plutil -lint "$PLIST_PATH" >/dev/null
assert_plist_value CFBundleIdentifier "com.mileschu.micai"
assert_plist_value CFBundleExecutable "MicAI"
assert_plist_value CFBundleIconFile "MicAI"
assert_plist_value CFBundlePackageType "APPL"
assert_plist_value LSMinimumSystemVersion "14.0"
assert_plist_value LSUIElement "true"
test -x "$EXECUTABLE_DIR/MicAI"
test -s "$ICON_PATH"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
