#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
APP_BUNDLE="$PROJECT_ROOT/dist/MicAI.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
EXECUTABLE_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICON_WORK_DIR="$PROJECT_ROOT/.build/micai-app-icon"
ICONSET_DIR="$ICON_WORK_DIR/MicAI.iconset"
ICON_GENERATOR="$ICON_WORK_DIR/generate-app-icon"
ICON_PATH="$RESOURCES_DIR/MicAI.icns"

if [ -n "${MICAI_SDKROOT:-}" ]; then
  export SDKROOT="$MICAI_SDKROOT"
elif [ -z "${SDKROOT:-}" ]; then
  SWIFT_VERSION="$(swift --version)"
  COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [[ "$SWIFT_VERSION" == *"Swift version 6.3."* ]] && [ -d "$COMPATIBLE_SDK" ]; then
    export SDKROOT="$COMPATIBLE_SDK"
  fi
fi

cd "$PROJECT_ROOT"
swift build --configuration release
BIN_DIR="$(swift build --configuration release --show-bin-path)"

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
swiftc "$PROJECT_ROOT/scripts/generate-app-icon.swift" \
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

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
