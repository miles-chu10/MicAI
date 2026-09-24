#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
export PROJECT_ROOT

# shellcheck source=scripts/codex-swift-env.sh
source "$SCRIPT_DIR/codex-swift-env.sh"

MICAI_TEST_ARGS=()
MICAI_TESTING_SHIM_ENABLED=0
MICAI_TESTING_PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
MICAI_TESTING_FRAMEWORK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework
MICAI_TESTING_INTEROP=/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib
MICAI_TEST_SWIFT_VERSION="$("$MICAI_SWIFT_BIN" --version 2>/dev/null)"
if [[ "$MICAI_TEST_SWIFT_VERSION" == *"Swift version 6.4"* ]] &&
  [ "$(/usr/bin/xcode-select -p 2>/dev/null || true)" = /Library/Developer/CommandLineTools ] &&
  [ -f "$MICAI_TESTING_PLUGIN" ] &&
  [ -d "$MICAI_TESTING_FRAMEWORK" ] &&
  [ -f "$MICAI_TESTING_INTEROP" ]; then
  # Swift 6.4 CLT includes Swift Testing, but SwiftPM does not discover its
  # macro or runtime locations without the Xcode app bundle.
  for MICAI_TEST_CONFIGURATION in Debug Release; do
    MICAI_TEST_PRODUCT_DIR="$MICAI_SWIFT_SCRATCH_PATH/out/Products/$MICAI_TEST_CONFIGURATION"
    mkdir -p "$MICAI_TEST_PRODUCT_DIR/PackageFrameworks"
    ln -sfn "$MICAI_TESTING_FRAMEWORK" \
      "$MICAI_TEST_PRODUCT_DIR/PackageFrameworks/Testing.framework"
    ln -sfn "$MICAI_TESTING_INTEROP" \
      "$MICAI_TEST_PRODUCT_DIR/lib_TestingInterop.dylib"
  done
  MICAI_TEST_ARGS=(
    -Xswiftc -load-plugin-library
    -Xswiftc "$MICAI_TESTING_PLUGIN"
  )
  MICAI_TESTING_SHIM_ENABLED=1
fi
unset MICAI_TESTING_PLUGIN MICAI_TESTING_FRAMEWORK MICAI_TESTING_INTEROP
unset MICAI_TEST_CONFIGURATION MICAI_TEST_PRODUCT_DIR MICAI_TEST_SWIFT_VERSION

cd "$PROJECT_ROOT"
if [ "$MICAI_TESTING_SHIM_ENABLED" -eq 1 ]; then
  exec "$MICAI_SWIFT_BIN" test --scratch-path "$MICAI_SWIFT_SCRATCH_PATH" \
    "${MICAI_TEST_ARGS[@]}" "$@"
fi
exec "$MICAI_SWIFT_BIN" test --scratch-path "$MICAI_SWIFT_SCRATCH_PATH" "$@"
