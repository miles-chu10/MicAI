#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET_TRIPLE="${MICAI_IOS_SIM_TARGET:-arm64-apple-ios17.0-simulator}"
WORK_DIR="$PROJECT_ROOT/.build/ios-simulator-manual"
MODULE_DIR="$WORK_DIR/modules"
MODULE_CACHE="$WORK_DIR/module-cache"
CORE_OBJECT="$WORK_DIR/ProofCarryingDraft.o"
APP_BUNDLE="$PROJECT_ROOT/dist-ios/MicAIiOS.app"
APP_EXECUTABLE="$APP_BUNDLE/MicAIiOS"

case "$APP_BUNDLE" in
  "$PROJECT_ROOT/dist-ios/MicAIiOS.app") ;;
  *)
    echo "Refusing unexpected iOS app path: $APP_BUNDLE" >&2
    exit 1
    ;;
esac

if [ -e "$APP_BUNDLE" ]; then
  find "$APP_BUNDLE" -depth -delete
fi
mkdir -p "$WORK_DIR" "$MODULE_DIR" "$MODULE_CACHE" "$APP_BUNDLE"

swiftc \
  -target "$TARGET_TRIPLE" \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -module-name MicAICore \
  -module-cache-path "$MODULE_CACHE" \
  -emit-module \
  -emit-module-path "$MODULE_DIR/MicAICore.swiftmodule" \
  -emit-object \
  "$PROJECT_ROOT/Sources/MicAICore/Proof/ProofCarryingDraft.swift" \
  -o "$CORE_OBJECT"

swiftc \
  -target "$TARGET_TRIPLE" \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -I "$MODULE_DIR" \
  "$CORE_OBJECT" \
  "$PROJECT_ROOT/Sources/MicAIiOS/MicAIiOSApp.swift" \
  "$PROJECT_ROOT/Sources/MicAIiOS/IOSUIEvidenceReporter.swift" \
  -o "$APP_EXECUTABLE"

install -m 644 "$PROJECT_ROOT/Resources/iOS/Info.plist" "$APP_BUNDLE/Info.plist"
chmod 755 "$APP_EXECUTABLE"
/usr/bin/plutil -lint "$APP_BUNDLE/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP_BUNDLE" >/dev/null
/usr/bin/codesign --verify --strict "$APP_BUNDLE"
test -x "$APP_EXECUTABLE"

echo "Built $APP_BUNDLE for $TARGET_TRIPLE"
